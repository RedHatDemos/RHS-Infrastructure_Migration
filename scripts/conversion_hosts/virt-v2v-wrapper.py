#!/usr/bin/python2
#
# Copyright (c) 2018 Red Hat, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

from contextlib import contextmanager
import json
import logging
import os
import pycurl
import re
import signal
import sys
import tempfile
import time

import ovirtsdk4 as sdk
import six

from urlparse import urlparse

if six.PY2:
    import subprocess32 as subprocess
    DEVNULL = open(os.devnull, 'r+')
else:
    import subprocess
    xrange = range
    DEVNULL = subprocess.DEVNULL

# Wrapper version
VERSION = "6"

LOG_LEVEL = logging.DEBUG
STATE_DIR = '/tmp'
TIMEOUT = 300
VDSM_LOG_DIR = '/var/log/vdsm/import'
VDSM_MOUNTS = '/rhev/data-center/mnt'
VDSM_UID = 36
VDSM_CA = '/etc/pki/vdsm/certs/cacert.pem'

# For now there are limited possibilities in how we can select allocation type
# and format. The best thing we can do now is to base the allocation on type of
# target storage domain.
PREALLOCATED_STORAGE_TYPES = (
    sdk.types.StorageType.CINDER,
    sdk.types.StorageType.FCP,
    sdk.types.StorageType.GLUSTERFS,
    sdk.types.StorageType.ISCSI,
    sdk.types.StorageType.POSIXFS,
    )

# Tweaks
VDSM = True
# We cannot use the libvirt backend in virt-v2v and have to use direct backend
# for several reasons:
# - it is necessary on oVirt host when running as root; and we need to run as
#   root when using export domain as target (we use vdsm user for other
#   targets)
# - SSH transport method cannot be used with libvirt because it does not pass
#   SSH_AUTH_SOCK env. variable to the QEMU process
DIRECT_BACKEND = True


def error(msg):
    """
    Function to produce an error and terminate the wrapper.

    WARNING: This can be used only at the early initialization stage! Do NOT
    use this once the password files are written or there are any other
    temporary data that should be removed at exit. This function uses
    sys.exit() which overcomes the code responsible for removing the files.
    """
    logging.error(msg)
    sys.stderr.write(msg)
    sys.exit(1)


def make_vdsm(data):
    """Makes sure the process runs as vdsm user"""
    uid = os.geteuid()
    if uid == VDSM_UID:
        # logging.debug('Already running as vdsm user')
        return
    elif uid == 0:
        # We need to drop privileges and become vdsm user, but we also need the
        # proper environment for the user which is tricky to get. The best
        # thing we can do is spawn another instance. Unfortunately we have
        # already read the data from stdin.
        # logging.debug('Starting instance as vdsm user')
        cmd = '/usr/bin/sudo'
        args = [cmd, '-u', 'vdsm']
        args.extend(sys.argv)
        wrapper = subprocess.Popen(args,
                                   stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE)
        out, err = wrapper.communicate(json.dumps(data))
        # logging.debug('vdsm instance finished')
        sys.stdout.write(out)
        sys.stderr.write(err)
        # logging.debug('Terminating root instance')
        sys.exit(wrapper.returncode)
    sys.stderr.write('Need to run as vdsm user or root!\n')
    sys.exit(1)


def daemonize():
    """Properly deamonizes the process and closes file desriptors."""
    sys.stderr.flush()
    sys.stdout.flush()

    pid = os.fork()
    if pid != 0:
        # Nothing more to do for the parent
        sys.exit(0)

    os.setsid()
    pid = os.fork()
    if pid != 0:
        # Nothing more to do for the parent
        sys.exit(0)

    os.umask(0)
    os.chdir('/')

    dev_null = open('/dev/null', 'w')
    os.dup2(dev_null.fileno(), sys.stdin.fileno())
    os.dup2(dev_null.fileno(), sys.stdout.fileno())
    os.dup2(dev_null.fileno(), sys.stderr.fileno())

    # Re-initialize cURL. This is necessary to re-initialze the PKCS #11
    # security tokens in NSS. Otherwise any use of SDK after the fork() would
    # lead to the error:
    #
    #    A PKCS #11 module returned CKR_DEVICE_ERROR, indicating that a
    #    problem has occurred with the token or slot.
    #
    pycurl.global_cleanup()
    pycurl.global_init(pycurl.GLOBAL_ALL)


class OutputParser(object):

    COPY_DISK_RE = re.compile(br'.*Copying disk (\d+)/(\d+) to.*')
    DISK_PROGRESS_RE = re.compile(br'\s+\((\d+\.\d+)/100%\)')
    NBDKIT_DISK_PATH_RE = re.compile(
        br'nbdkit: debug: Opening file (.*) \(.*\)')
    OVERLAY_SOURCE_RE = re.compile(
        br' *overlay source qemu URI: json:.*"file\.path": ?"([^"]+)"')
    VMDK_PATH_RE = re.compile(
            br'/vmfs/volumes/(?P<store>[^/]*)/(?P<vm>[^/]*)/'
            + br'(?P<disk>.*)(-flat)?\.vmdk')
    RHV_DISK_UUID = re.compile(br'disk\.id = \'(?P<uuid>[a-fA-F0-9-]*)\'')

    def __init__(self, v2v_log):
        self._log = open(v2v_log, 'rbU')
        self._current_disk = None
        self._current_path = None

    def parse(self, state):
        line = None
        while line != b'':
            line = self._log.readline()
            m = self.COPY_DISK_RE.match(line)
            if m is not None:
                try:
                    self._current_disk = int(m.group(1))-1
                    self._current_path = None
                    state['disk_count'] = int(m.group(2))
                    logging.info('Copying disk %d/%d',
                                 self._current_disk+1, state['disk_count'])
                    if state['disk_count'] != len(state['disks']):
                        logging.warning(
                            'Number of supplied disk paths (%d) does not match'
                            ' number of disks in VM (%s)',
                            len(state['disks']),
                            state['disk_count'])
                except ValueError:
                    logging.exception('Conversion error')

            # VDDK
            m = self.NBDKIT_DISK_PATH_RE.match(line)
            if m is not None:
                self._current_path = m.group(1).decode()
                if self._current_disk is not None:
                    logging.info('Copying path: %s', self._current_path)
                    self._locate_disk(state)

            # SSH
            m = self.OVERLAY_SOURCE_RE.match(line)
            if m is not None:
                path = m.group(1).decode()
                # Transform path to be raltive to storage
                self._current_path = self.VMDK_PATH_RE.sub(
                    br'[\g<store>] \g<vm>/\g<disk>', path)
                if self._current_disk is not None:
                    logging.info('Copying path: %s', self._current_path)
                    self._locate_disk(state)

            m = self.DISK_PROGRESS_RE.match(line)
            if m is not None:
                if self._current_path is not None and \
                        self._current_disk is not None:
                    try:
                        state['disks'][self._current_disk]['progress'] = \
                            float(m.group(1))
                        logging.debug('Updated progress: %s', m.group(1))
                    except ValueError:
                        logging.exception('Conversion error')
                else:
                    logging.debug('Skipping progress update for unknown disk')

            m = self.RHV_DISK_UUID.match(line)
            if m is not None:
                path = state['disks'][self._current_disk]['path']
                disk_id = m.group('uuid')
                state['internal']['disk_ids'][path] = disk_id
                logging.debug('Path \'%s\' has disk id=\'%s\'', path, disk_id)
        return state

    def close(self):
        self._log.close()

    def _locate_disk(self, state):
        if self._current_disk is None:
            # False alarm, not copying yet
            return

        # NOTE: We assume that _current_disk is monotonic
        for i in xrange(self._current_disk, len(state['disks'])):
            if state['disks'][i]['path'] == self._current_path:
                if i == self._current_disk:
                    # We have correct index
                    logging.debug('Found path at correct index')
                else:
                    # Move item to current index
                    logging.debug('Moving path from index %d to %d', i,
                                  self._current_disk)
                    d = state['disks'].pop(i)
                    state['disks'].insert(self._current_disk, d)
                return

        # Path not found
        logging.debug('Path \'%s\' not found in %r', self._current_path,
                      state['disks'])
        state['disks'].insert(
            self._current_disk,
            {
                'path': self._current_path,
                'progress': 0,
            })


@contextmanager
def log_parser(v2v_log):
    parser = None
    try:
        parser = OutputParser(v2v_log)
        yield parser
    finally:
        if parser is not None:
            parser.close()


@contextmanager
def sdk_connection(data):
    connection = None
    url = urlparse(data['rhv_url'])
    username = url.username if url.username is not None else 'admin@internal'
    try:
        insecure = data['insecure_connection']
        connection = sdk.Connection(
            url=str(data['rhv_url']),
            username=str(username),
            password=str(data['rhv_password']),
            ca_file=str(data['rhv_cafile']),
            log=logging.getLogger(),
            insecure=insecure,
        )
        yield connection
    finally:
        if connection is not None:
            connection.close()


def is_iso_domain(path):
    """
    Check if domain is ISO domain. @path is path to domain metadata file
    """
    try:
        logging.debug('is_iso_domain check for %s', path)
        with open(path, 'r') as f:
            for line in f:
                if line.rstrip() == 'CLASS=Iso':
                    return True
    except OSError:
        logging.exception('Failed to read domain metadata')
    except IOError:
        logging.exception('Failed to read domain metadata')
    return False


def find_iso_domain():
    """
    Find path to the ISO domain from available domains mounted on host
    """
    if not os.path.isdir(VDSM_MOUNTS):
        logging.error('Cannot find RHV domains')
        return None
    for sub in os.walk(VDSM_MOUNTS):

        if 'dom_md' in sub[1]:
            # This looks like a domain so focus on metadata only
            try:
                del sub[1][sub[1].index('master')]
            except ValueError:
                pass
            try:
                del sub[1][sub[1].index('images')]
            except ValueError:
                pass
            continue

        if 'blockSD' in sub[1]:
            # Skip block storage domains, we don't support ISOs there
            del sub[1][sub[1].index('blockSD')]

        if 'metadata' in sub[2] and \
                os.path.basename(sub[0]) == 'dom_md' and \
                is_iso_domain(os.path.join(sub[0], 'metadata')):
            return os.path.join(
                os.path.dirname(sub[0]),
                'images',
                '11111111-1111-1111-1111-111111111111')
    return None


def write_state(state):
    state = state.copy()
    del state['internal']
    with open(state_file, 'w') as f:
        json.dump(state, f)


def wrapper(data, state, v2v_log, agent_sock=None):
    v2v_args = [
        '/usr/bin/virt-v2v', '-v', '-x',
        data['vm_name'],
        '-of', data['output_format'],
        '--bridge', 'ovirtmgmt',
        '--root', 'first'
    ]

    if data['transport_method'] == 'vddk':
        v2v_args.extend([
            '-i', 'libvirt',
            '-ic', data['vmware_uri'],
            '-it', 'vddk',
            '-io', 'vddk-libdir=%s' % '/opt/vmware-vix-disklib-distrib',
            '-io', 'vddk-thumbprint=%s' % data['vmware_fingerprint'],
            '--password-file', data['vmware_password_file'],
            ])
    elif data['transport_method'] == 'ssh':
        v2v_args.extend([
            '-i', 'vmx',
            '-it', 'ssh',
            ])

    if 'rhv_url' in data:
        v2v_args.extend([
            '-o', 'rhv-upload',
            '-oc', data['rhv_url'],
            '-os', data['rhv_storage'],
            '-op', data['rhv_password_file'],
            '-oo', 'rhv-cafile=%s' % data['rhv_cafile'],
            '-oo', 'rhv-cluster=%s' % data['rhv_cluster'],
            '-oo', 'rhv-direct',
            ])
        if data['insecure_connection']:
            v2v_args.extend(['-oo', 'rhv-verifypeer=%s' %
                            ('false' if data['insecure_connection'] else
                             'true')])

    elif 'export_domain' in data:
        v2v_args.extend([
            '-o', 'rhv',
            '-os', data['export_domain'],
            ])

    if 'allocation' in data:
        v2v_args.extend([
            '-oa', data['allocation']
            ])

    if 'network_mappings' in data:
        for mapping in data['network_mappings']:
            v2v_args.extend(['--bridge', '%s:%s' %
                            (mapping['source'], mapping['destination'])])

    # Prepare environment
    env = os.environ.copy()
    env['LANG'] = 'C'
    if DIRECT_BACKEND:
        logging.debug('Using direct backend. Hack, hack...')
        env['LIBGUESTFS_BACKEND'] = 'direct'
    if 'virtio_win' in data:
        env['VIRTIO_WIN'] = data['virtio_win']
    if agent_sock is not None:
        env['SSH_AUTH_SOCK'] = agent_sock

    proc = None
    with open(v2v_log, 'w') as log:
        logging.info('Starting virt-v2v as: %r, environment: %r',
                     v2v_args, env)
        proc = subprocess.Popen(
                v2v_args,
                stdin=DEVNULL,
                stderr=subprocess.STDOUT,
                stdout=log,
                env=env,
                )

    try:
        state['started'] = True
        state['pid'] = proc.pid
        write_state(state)
        with log_parser(v2v_log) as parser:
            while proc.poll() is None:
                state = parser.parse(state)
                write_state(state)
                time.sleep(5)
            logging.info('virt-v2v terminated with return code %d',
                         proc.returncode)
            state = parser.parse(state)
    except Exception:
        logging.exception('Error while monitoring virt-v2v')
        if proc.poll() is None:
            logging.info('Killing virt-v2v process')
            proc.kill()

    state['return_code'] = proc.returncode
    write_state(state)

    if proc.returncode != 0:
        state['failed'] = True
    write_state(state)


def write_password(password, password_files):
    pfile = tempfile.mkstemp(suffix='.v2v')
    password_files.append(pfile[1])
    os.write(pfile[0], bytes(password.encode('utf-8')))
    os.close(pfile[0])
    return pfile[1]


def spawn_ssh_agent(data):
    try:
        out = subprocess.check_output(['ssh-agent'])
        logging.debug('ssh-agent: %s' % out)
        sock = re.search(br'^SSH_AUTH_SOCK=([^;]+);', out, re.MULTILINE)
        pid = re.search(br'^echo Agent pid ([0-9]+);', out, re.MULTILINE)
        if not sock or not pid:
            logging.error(
                'Incomplete match of ssh-agent output; sock=%r; pid=%r',
                sock, pid)
            return None, None
        agent_sock = sock.group(1).decode()
        agent_pid = int(pid.group(1))
        logging.info('SSH Agent started with PID %d', agent_pid)
    except subprocess.CalledProcessError:
        logging.error('Failed to start ssh-agent')
        return None, None
    env = os.environ.copy()
    env['SSH_AUTH_SOCK'] = agent_sock
    cmd = ['ssh-add']
    if 'ssh_key_file' in data:
        logging.info('Using custom SSH key')
        cmd.append(data['ssh_key_file'])
    else:
        logging.info('Using SSH key(s) from ~/.ssh')
    ret_code = subprocess.call(cmd, env=env)
    if ret_code != 0:
        logging.error('Failed to add SSH keys to the agent! ssh-add'
                      ' terminated with return code %d', ret_code)
        os.kill(agent_pid, signal.SIGTERM)
        return None, None
    return agent_pid, agent_sock


def check_install_drivers(data):
    if 'virtio_win' in data and os.path.isabs(data['virtio_win']):
        full_path = data['virtio_win']
    else:
        iso_domain = find_iso_domain()

        iso_name = data.get('virtio_win')
        if iso_name is not None:
            if iso_domain is None:
                error('ISO domain not found')
        else:
            if iso_domain is None:
                # This is not an error
                logging.warning('ISO domain not found' +
                                ' (but install_drivers is true).')
                data['install_drivers'] = False
                return

            # (priority, pattern)
            patterns = [
                (4, br'RHV-toolsSetup_([0-9._]+)\.iso'),
                (3, br'RHEV-toolsSetup_([0-9._]+)\.iso'),
                (2, br'oVirt-toolsSetup_([a-z0-9._-]+)\.iso'),
                (1, br'virtio-win-([0-9.]+).iso'),
                ]
            patterns = [(p[0], re.compile(p[1], re.IGNORECASE))
                        for p in patterns]
            best_name = None
            best_version = None
            best_priority = -1
            for fname in os.listdir(iso_domain):
                if not os.path.isfile(os.path.join(iso_domain, fname)):
                    continue
                for priority, pat in patterns:
                    m = pat.match(fname)
                    if not m:
                        continue
                    version = m.group(1)
                    logging.debug('Matched ISO %r (priority %d)',
                                  fname, priority)
                    if best_version is None or \
                            (best_version < version and
                             best_priority <= priority):
                        best_name = fname
                        best_version = version

            if best_name is None:
                # Nothing found, this is not an error
                logging.warn('Could not find any ISO with drivers' +
                             ' (but install_drivers is true).')
                data['install_drivers'] = False
                return
            iso_name = best_name

        full_path = os.path.join(iso_domain, iso_name)

    if not os.path.isfile(full_path):
        error("'virtio_win' must be a path or file name of image in "
              "ISO domain")
    data['virtio_win'] = full_path
    logging.info("virtio_win (re)defined as: %s", data['virtio_win'])


def handle_cleanup(data, state):
    with sdk_connection(data) as conn:
        disks_service = conn.system_service().disks_service()
        transfers_service = conn.system_service().image_transfers_service()
        disk_ids = state['internal']['disk_ids'].values()
        # First stop all active transfers...
        try:
            transfers = transfers_service.list()
            transfers = [t for t in transfers if t.image.id in disk_ids]
            if len(transfers) == 0:
                logging.debug('No active transfers to cancel')
            for transfer in transfers:
                logging.info('Canceling transfer id=%s for disk=%s',
                             transfer.id, transfer.image.id)
                transfer_service = transfers_service.image_transfer_service(
                    transfer.id)
                transfer_service.cancel()
                # The incomplete disk will be removed automatically
                disk_ids.remove(transfer.image.id)
        except sdk.Error:
            logging.exception('Failed to cancel transfers')

        # ... then delete the uploaded disks
        logging.info('Removing disks: %r', disk_ids)
        endt = time.time() + TIMEOUT
        while len(disk_ids) > 0:
            for disk_id in disk_ids:
                try:
                    disk_service = disks_service.disk_service(disk_id)
                    disk = disk_service.get()
                    if disk.status != sdk.types.DiskStatus.OK:
                        continue
                    logging.info('Removing disk id=%s', disk_id)
                    disk_service.remove()
                    disk_ids.remove(disk_id)
                except sdk.Error:
                    logging.exception('Failed to remove disk id=%s',
                                      disk_id)
            if time.time() > endt:
                logging.error('Timed out waiting for disks: %r', disk_ids)
                break
            time.sleep(1)


###########

# Read and parse input -- hopefully this should be safe to do as root
data = json.load(sys.stdin)

# NOTE: this is just pre-check to find out whether we can run as vdsm user at
# all. This is not validation of the input data!
if 'export_domain' in data:
    # Need to be root to mount NFS share
    VDSM = False
    # Cannot use libvirt backend as root on VDSM host due to permissions
    DIRECT_BACKEND = True

if VDSM:
    make_vdsm(data)

# The logging is delayed after we now which user runs the wrapper. Otherwise we
# would have two logs.
log_tag = '%s-%d' % (time.strftime('%Y%m%dT%H%M%S'), os.getpid())
v2v_log = os.path.join(VDSM_LOG_DIR, 'v2v-import-%s.log' % log_tag)
wrapper_log = os.path.join(VDSM_LOG_DIR, 'v2v-import-%s-wrapper.log' % log_tag)
state_file = os.path.join(STATE_DIR, 'v2v-import-%s.state' % log_tag)

logging.basicConfig(
    level=LOG_LEVEL,
    filename=wrapper_log,
    format='%(asctime)s:%(levelname)s: %(message)s (%(module)s:%(lineno)d)')

logging.info('Wrapper version %s, uid=%d', VERSION, os.getuid())

logging.info('Will store virt-v2v log in: %s', v2v_log)
logging.info('Will store state file in: %s', state_file)

password_files = []

try:
    # Make sure all the needed keys are in data. This is rather poor
    # validation, but...
    if 'vm_name' not in data:
            error('Missing vm_name')

    # Output file format (raw or qcow2)
    if 'output_format' in data:
        if data['output_format'] not in ('raw', 'qcow2'):
            error('Invalid output format %r, expected raw or qcow2' %
                  data['output_format'])
    else:
        data['output_format'] = 'raw'

    # Transports (only VDDK for now)
    if 'transport_method' not in data:
        error('No transport method specified')
    if data['transport_method'] not in ('ssh', 'vddk'):
        error('Unknown transport method: %s', data['transport_method'])

    if data['transport_method'] == 'vddk':
        for k in [
                'vmware_fingerprint',
                'vmware_uri',
                'vmware_password',
                ]:
            if k not in data:
                error('Missing argument: %s' % k)

    # Targets (only export domain for now)
    if 'rhv_url' in data:
        for k in [
                'rhv_cluster',
                'rhv_password',
                'rhv_storage',
                ]:
            if k not in data:
                error('Missing argument: %s' % k)
        if 'rhv_cafile' not in data:
            logging.info('Path to CA certificate not specified,'
                         ' trying VDSM default: %s', VDSM_CA)
            data['rhv_cafile'] = VDSM_CA
    elif 'export_domain' in data:
        pass
    else:
        error('No target specified')

    # Network mappings
    if 'network_mappings' in data:
        if isinstance(data['network_mappings'], list):
            for mapping in data['network_mappings']:
                if not all(k in mapping for k in ("source", "destination")):
                    error("Both 'source' and 'destination' must be provided"
                          + " in network mapping")
        else:
            error("'network_mappings' must be an array")

    # Virtio drivers
    if 'virtio_win' in data:
        # This is for backward compatibility
        data['install_drivers'] = True
    if 'install_drivers' in data:
        check_install_drivers(data)
    else:
        data['install_drivers'] = False

    # Insecure connection
    if 'insecure_connection' not in data:
        data['insecure_connection'] = False
    if data['insecure_connection']:
        logging.info('SSL verification is disabled for oVirt SDK connections')

    # Allocation type
    if 'allocation' in data:
        if data['allocation'] not in ('preallocated', 'sparse'):
            error('Invalid value for allocation type: %r' % data['allocation'])
    else:
        # Check storage domain type and decide on suitable allocation type
        # Note: This is only temporary. We should get the info from the caller
        # in the future.
        domain_type = None
        with sdk_connection(data) as c:
            service = c.system_service().storage_domains_service()
            domains = service.list(search='name="%s"' %
                                   str(data['rhv_storage']))
            if len(domains) != 1:
                error('Found %d domains matching "%s"!' % data['rhv_storage'])
            domain_type = domains[0].storage.type
        logging.info('Storage domain "%s" is of type %r', data['rhv_storage'],
                     domain_type)
        data['allocation'] = 'sparse'
        if domain_type in PREALLOCATED_STORAGE_TYPES:
            data['allocation'] = 'preallocated'
        logging.info('... selected allocation type is %s', data['allocation'])

    #
    # NOTE: don't use error() beyond this point!
    #

    # Store password(s)
    logging.info('Writing password file(s)')
    if 'vmware_password' in data:
        data['vmware_password_file'] = write_password(data['vmware_password'],
                                                      password_files)
    if 'rhv_password' in data:
        data['rhv_password_file'] = write_password(data['rhv_password'],
                                                   password_files)
    if 'ssh_key' in data:
        data['ssh_key_file'] = write_password(data['ssh_key'],
                                              password_files)

    # Create state file before dumping the JSON
    state = {
            'disks': [],
            'internal': {
                'disk_ids': {},
                },
            }
    try:
        if 'source_disks' in data:
            logging.debug('Initializing disk list from %r',
                          data['source_disks'])
            for d in data['source_disks']:
                state['disks'].append({
                    'path': d,
                    'progress': 0})
            state['disk_count'] = len(data['source_disks'])
        write_state(state)

        # Send some useful info on stdout in JSON
        print(json.dumps({
            'v2v_log': v2v_log,
            'wrapper_log': wrapper_log,
            'state_file': state_file,
        }))

        # Let's get to work
        logging.info('Daemonizing')
        daemonize()
        agent_pid = None
        agent_sock = None
        if data['transport_method'] == 'ssh':
            agent_pid, agent_sock = spawn_ssh_agent(data)
            if agent_pid is None:
                raise RuntimeError('Failed to start ssh-agent')
        wrapper(data, state, v2v_log, agent_sock)
        if agent_pid is not None:
            os.kill(agent_pid, signal.SIGTERM)

    except Exception:
        # No need to log the exception, it will get logged below
        logging.error('An error occured, finishing state file...')
        state['failed'] = True
        write_state(state)
        raise
    finally:
        if 'failed' in state:
            # Perform cleanup after failed conversion
            logging.debug('Cleanup phase')
            try:
                handle_cleanup(data, state)
            finally:
                state['finished'] = True
                write_state(state)

    # Remove password files
    logging.info('Removing password files')
    for f in password_files:
        try:
            os.remove(f)
        except OSError:
            logging.exception('Error while removing password file: %s' % f)

    state['finished'] = True
    write_state(state)

except Exception:
    logging.exception('Wrapper failure')
    # Remove password files
    logging.info('Removing password files')
    for f in password_files:
        try:
            os.remove(f)
        except OSError:
            logging.exception('Error removing password file: %s' % f)
    # Re-raise original error
    raise

logging.info('Finished')
