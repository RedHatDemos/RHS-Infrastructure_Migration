###################################
#
# CloudForms Automate Method: Convert Image
#
# This method is used to Convert OVA image to raw
###################################
begin
  require 'net/ssh'
  require 'fileutils'

  # Method for logging
  #
  # * Args    :
  #   level:: logging level
  #   message:: message to log
  def log(level, message)
    $evm.log(level, "#{@method} - #{message}")
  end

  # Sets the state machine to retry in 15 minutes and exits
  def retry_v2v
    $evm.root['ae_result']         = 'retry'
    $evm.root['ae_retry_interval'] = $evm.object['check_convert_interval'] || '15.minutes'
    log(:info, "V2V working. Checking in #{$evm.root['ae_retry_interval']}")
    exit MIQ_OK
  end

  # Sets all custom attributes made in this method to nil. Used for error handling.
  def reset_convert_status
    @vm.custom_set(:v2v_counter, nil)
    @vm.custom_set(:v2v_log, nil)
    @vm.custom_set(:wrapper_log, nil)
    @vm.custom_set(:v2v_success, nil)
    @vm.custom_set(:sysprep_log, nil)
  end

  # Sets the custom attributes to the vm
  #
  # * Args    :
  #   vm:: vm to set attributes on
  #   counter:: counter file to use
  #   log:: name of the log file to check the status of the ova export
  def set_custom_attributes(counter, log, wrapper_log, sysprep_log)
    @vm.custom_set(:v2v_counter, counter)
    @vm.custom_set(:v2v_log, log) unless log.nil?
    @vm.custom_set(:wrapper_log, wrapper_log) unless wrapper_log.nil?
    @vm.custom_set(:sysprep_log, sysprep_log) unless sysprep_log.nil?
  end

  # Finds the vm in either root, object, or by guid
  #
  # * Returns :
  #   vm:: vm object
  def get_vm
    @vm = $evm.root['vm'] || $evm.object['vm']

    if @vm.nil?
      log(:warn, "VM was not found in root or object when coming back from retry in  #{@current_state}.")

      guid = $evm.root['dialog_guid'] || $evm.root['guid']

      @vm = $evm.vmdb('vm').find_by_guid(guid)
      log(:info, 'Found VM by guid') unless @vm.nil?
      raise 'VM not found' if @vm.nil?

      $evm.root['vm'] = @vm
    end
  end

  # Find number of running convert process
  #
  # *Param :
  # server:: migration server to check
  #
  # *Returns :
  # number_of_processes:: number of running processes on given server
  def get_number_of_running_converts(server)
    pid_directory = "#{$base_directory}/running/#{server}"
    File.exists?(pid_directory) ? Dir.entries(pid_directory).size-2 : 0
  end

  # Find the migration machine with the least work load
  #
  # *Returns :
  # migration_machine:: ip of migration machine with least work load
  def get_available_migration_server
    migration_servers    = $evm.object['migration_server_ipaddrs']
    least_running_number = nil
    least_busy_server    = nil
    migration_servers.each { |server|
      number_running = get_number_of_running_converts(server)
      if number_running==0
        least_busy_server=server
        break
      elsif least_busy_server.nil? || number_running < least_running_number
        least_busy_server    =server
        least_running_number = number_running
      end
    }
    log(:info, "LEAST BUSY V2V BOX: #{least_busy_server}")
    return least_busy_server
  end

  # Determines if the vm has already ran the through v2v successfully
  #
  # *Returns :
  # boolean:: true if the vm has the v2v_success flag and the disks are located
  # def converted?
  #   if @vm.custom_get(:v2v_success)
  #     (1..@vm.num_hard_disks).each do |index|
  #       convert_vol = "#{$converted_location}/#{@vm.name}-sd#{(index + 96).chr}"
  #       unless File.exist?(convert_vol)
  #         log(:info, "Could not find converted volume #{convert_vol}. Continuing with conversion.")
  #         return false
  #       end
  #     end
  #   else
  #     log(:info, 'No success attribute found. Continuing with conversion.')
  #     return false
  #   end
  #   return true
  # end

  @method = 'convert_image'
  log(:info, "#{@method} - CloudForms Automate Method Started")

  @current_state = $evm.root['ae_state']
  get_vm
  #  @state_machine = $evm.instance_get('/RHC/Migration/StateMachines/Migrate/migrate')

  stp_task    = $evm.root['service_template_provision_task']
  miq_request = stp_task.miq_request unless stp_task.nil?
  miq_request.set_message("#{@vm.name}: #{@method}") unless miq_request.nil?

  # Start Here
  @dev = false

  # Dependent on conversion and volume renaming for skipping since steps are coupled
  if @vm.custom_get(:v2v_success) and @vm.custom_get(:move_success)
    log(:info, "#{@current_state} ran successfully previously, skipping this step")
    exit MIQ_OK
  end

  $migration_servers         = $evm.object['migration_server_ipaddrs']
  $migration_server_password = $evm.object.decrypt('migration_server_password')
  $migration_server_user     = $evm.object['migration_server_user']

  # PLEASE don't change ordering of these attributes, they are dependent upon the ones above them
  $base_directory            = '/mnt/migrate/convert'
  $converted_location        = "/mnt/openstack/convert/#{@vm.name}"
  $rhev_export_path          = "/mnt/migrate/rhev/export"
  $log_location              = "#{$base_directory}/#{@vm.name}"
  @script_dir                = '/mnt/migrate/tools'
  @temp_dir                  = '/mnt/migrate/temp'

  $available_migration_server = get_available_migration_server
  $pids_location              = "#{$base_directory}/running/#{$available_migration_server}"

  FileUtils.mkdir_p $base_directory, :mode => 0777 unless File.exists?($base_directory)
  FileUtils.mkdir_p $pids_location, :mode => 0777 unless File.exists?($pids_location)
  FileUtils.mkdir_p $log_location, :mode => 0777 unless File.exists?($log_location)
  FileUtils.mkdir_p @temp_dir, :mode => 0777 unless File.exists?(@temp_dir)


  ip_addrs    = @vm.custom_get(:ip)
  log(:info, "==> got custom ips: [#{ip_addrs}]")
  ip_addrs    = ip_addrs.split(',') unless ip_addrs.nil?
  unless ip_addrs[0].nil?
    @eth0cfg = "-I #{ip_addrs[0]}"
  else
    @eth0cfg = ""
  end
  nics = ip_addrs.length

  fmt         = '%Y%m%d_%H%M'
  time_stamp  = Time.now.strftime(fmt)
  v2v_log     = "#{$log_location}/#{@vm.name}_#{time_stamp}.log"
  sysprep_log = "#{$log_location}/sysprep_#{@vm.name}_#{time_stamp}.log"
  wrapper_log = "#{$log_location}/wrapper_#{@vm.name}_#{time_stamp}.log"
  v2v_cap     = $evm.object['v2v_cap'] || 4

  if @vm.custom_get(:v2v_counter).nil?

    log(:info, "v2v cap is at #{v2v_cap}")
    if Dir.entries($pids_location).size - 2 >= v2v_cap
      log(:info, 'Too many conversions at the moment, waiting for a free v2v server.')
      miq_request.set_message("#{@vm.name}: #{@method} - waiting for a free v2v server") unless miq_request.nil?
      retry_v2v
    end

    log(:info, "SSH to #{$migration_server_user}@#{$available_migration_server}")
    miq_request.set_message("#{@vm.name}: #{@method} started on #{$available_migration_server}") unless miq_request.nil?

    Net::SSH.start($available_migration_server, $migration_server_user, :password => $migration_server_password) do |ssh|

      commands = []

      pod = "vmware"
      if @vm.ext_management_system.type == "EmsRedhat"
        pod = "redhat"
        ems = @vm.ext_management_system
        rhev_userid = ems.authentication_userid.gsub("\\", '%5c')
        rhev_pass = ems.authentication_password
        rhev_hostname = ems.hostname
        command = "#{@script_dir}/get_export.py #{@vm.name} #{rhev_userid} #{rhev_pass} https://#{rhev_hostname}"
        log(:info, "Executing : #{command}")
        ova = ssh.exec!(command)
        ova = ova.chomp
      else
        ova = "/mnt/migrate/ova/#{@vm.name}/#{@vm.name}.ova"
        FileUtils.chmod 0755, ova, :verbose => true
      end

      # If it's a linux vm, send a log location for virt-sysprep
      if @vm.os_image_name =~ /linux/i
        log(:info, "Checking for Rhev")
        if @vm.tagged_with?("poa","rhev")
          log(:info, "Is an RHEV provision")
          commands = [ "nohup #{@script_dir}/rhev_v2v.sh -i #{ova} -o #{$rhev_export_path} -t #{@temp_dir} -l #{v2v_log} -L #{sysprep_log} -n #{nics} #{@eth0cfg} > #{wrapper_log} 2>&1 &" ]
        else
          log(:info, "Is an OSP provision")
          commands = [ "nohup #{@script_dir}/v2v.sh -i #{ova} -o #{$converted_location} -t #{@temp_dir} -l #{v2v_log} -L #{sysprep_log} -n #{nics} #{@eth0cfg} > #{wrapper_log} 2>&1 &" ]
        end
      else
        if @vm.tagged_with?("poa","rhev")
          log(:info, "Is an RHEV provision")
          commands    = [ "nohup #{@script_dir}/rhev_v2v.sh -i #{ova} -o #{$rhev_export_path} -t #{@temp_dir} -l #{v2v_log} > #{wrapper_log} 2>&1 &" ]
        else
          log(:info, "Is an OSP provision")
          commands    = [ "nohup #{@script_dir}/v2v.sh -i #{ova} -o #{$converted_location} -t #{@temp_dir} -l #{v2v_log} > #{wrapper_log} 2>&1 &" ]
        end
        sysprep_log = nil
      end

      log(:info, "Executing : #{commands}")
      ssh.exec!(commands.join(';'))
    end

    file = File.new("#{$pids_location}/#{@vm.guid}.txt", mode='w')
    set_custom_attributes(file.path, v2v_log, wrapper_log, sysprep_log)
    log(:info, "Made corresponding counter file: #{file.path}")
    retry_v2v
  else
    contents_array = File.readlines(@vm.custom_get(:wrapper_log))
    result         = contents_array.last
    log(:info, "last line of #{@vm.custom_get(:wrapper_log)}: #{result}")

    if result =~ /Stop time/
      # Checking both logs. v2v log for success and sysprep log for error.
      v2v_success     = File.open(@vm.custom_get(:v2v_log), 'r') { |f| f.each_line.detect { |line| /Finishing off/i.match(line) } }
      sysprep_success = nil
      unless @vm.custom_get(:sysprep_log).nil?
        sysprep_success = File.open(@vm.custom_get(:sysprep_log), 'r') { |f| f.each_line.detect { |line| /error/i.match(line) } }
      end

      log(:info, "Line from #{@vm.custom_get(:v2v_log)} containing 'Finishing off' : #{v2v_success}")
      log(:info, "Line from #{@vm.custom_get(:sysprep_log)} containing 'error' : #{sysprep_success}")

      # want v2v success and don't want sysprep error
      if !v2v_success.nil? and sysprep_success.nil?
        FileUtils.rm @vm.custom_get(:v2v_counter) if File.exists?(@vm.custom_get(:v2v_counter))
        set_custom_attributes(nil, nil, nil, nil)
        @vm.custom_set(:v2v_success, true)
        log(:info, 'Successfully ran V2V tool. Cleaned up counter file and attributes.')
      else
        # Logging is done and Finishing off wasnt found in v2v log or error was found in sysprep log, so it errored.
        # Clean up and raise exception.
        FileUtils.rm @vm.custom_get(:v2v_counter) if File.exists?(@vm.custom_get(:v2v_counter))
        raise 'V2V conversion failed'
      end
    else
      # Still working
      convert_log = File.readlines(@vm.custom_get(:v2v_log))

      volume_converting=''
      convert_log.each do |x|
        if x.include?('qemu-img convert')
          volume_converting = x.chomp.split(/\//).last.chop
        end
      end

      result  = convert_log.last
      progress=result.split(/\r/).last.strip.match(/\((.*)%\)/)

      status = 'extracting vmdks'
      unless volume_converting.nil? || progress.nil?
        status = "#{volume_converting} #{progress}"
      end

      log(:info, "conversion in progress  #{status}")
      miq_request.set_message("#{@vm.name}: #{@method} - #{status}") unless miq_request.nil?
      retry_v2v
    end
  end

  ############
  # Exit method
  #
  miq_request.set_message("#{@vm.name}: #{@method} completed") unless miq_request.nil?
  log(:info, 'CloudForms Automate Method Ended')
  exit MIQ_OK

    #
    # Set Ruby rescue behavior
    #
rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  $evm.execute('tag_create', 'failed_migration', :name => @current_state, :description => @current_state)
  @vm.tag_assign("failed_migration/#{@current_state}")
  FileUtils.rm @vm.custom_get(:v2v_counter) if File.exists?(@vm.custom_get(:v2v_counter))
  reset_convert_status
  miq_request.user_message = "#{@vm.name}: #{@current_state} failed on worker #{$evm.root['miq_server'].name}" unless miq_request.nil?
  exit MIQ_ABORT
end
