#!/bin/sh 

host=$(hostname) 

##1 check vmware version  

{ 

echo "" 

echo "== 1.  Patch Version ==" 

echo "" 

vmware -v  

echo "" 

echo "---------------------------------------" 

}| tee -a ${host}_output.txt 

 

##2 NTP time configure 

{ 

echo "" 

echo "== 2.  System Setting (NTP Configuration)  ==" 

echo "" 

esxcli system ntp get 

echo "" 

echo "---------------------------------------" 

} | tee -a ${host}_output.txt 

 

##3 firewall enable ssh, vsphere client, httpclient 

  { 

echo "" 

echo "== 3.  ESX Host Firewall ==" 

echo "" 

esxcli network firewall ruleset set --ruleset-id=sshServer --enabled=true 

esxcli network firewall ruleset set --ruleset-id=vSphereClient --enabled=true 

esxcli network firewall ruleset set --ruleset-id=httpClient --enabled=true 

  # Show enabled firewall rules 

esxcli network firewall ruleset list | awk 'NR==1 || /sshServer|vSphereClient|httpClient/'   

echo "" 

echo "---------------------------------------" 

} | tee -a ${host}_output.txt 

 

##4 SNMP disable 

{ 

echo "" 

echo "== 4.  System Setting (SNMP) ==" 

echo "" 

esxcli system snmp set --enable false 

esxcli network firewall ruleset list | awk 'NR==1 || /snmp/'  

echo "" 

echo "---------------------------------------" 

} | tee -a ${host}_output.txt 

 

##5 show latested SSL certificate install 

{ 

echo "" 

echo "== 5. System Setting (SSL Certificate Revocation) ==" 

echo "" 

openssl x509 -in /etc/vmware/ssl/rui.crt -noout -text | grep -E 'Issuer:|Subject:|Not Before:|Not After :' 

 

echo "" 

echo "---------------------------------------" 

} | tee -a ${host}_output.txt 

 

##6 persistent logging  => leave default 

{ 

echo "" 

echo "== 6.  Logging ==" 

echo "" 

echo "Syslog.Global.Logdir = $(vim-cmd hostsvc/advopt/view Syslog.global.logDir | grep 'value =' | awk -F '= ' '{print $2}' | sed 's/\"//g')" 

echo "" 

echo "---------------------------------------" 

} | tee -a ${host}_output.txt 

 

##7 remote logging => not enable for OCU 

{ 

echo "" 

echo "== 7.  Remote Logging ==" 

echo "" 

echo "Syslog.Global.logHost = $(vim-cmd hostsvc/advopt/view Syslog.global.logHost | grep 'value =' | awk -F '= ' '{print $2}' | sed 's/\"//g')" 

echo "" 

echo "---------------------------------------" 

} | tee -a ${host}_output.txt 

 

##8 create new account edmacc,emerid,TSCMUsr,tmbsysadm 

 { 

# Function to create user, set password, assign role, and enable shell access 

create_user() { 

  user=$1 

  role=$2 

  password='P@ssw0rd123!' 

  

  #echo "Processing user: $user (Role: $role)" 

  

  # Create user if not exists 

  if ! grep -q "^$user:" /etc/passwd; then 

    echo "Creating user $user..." 

    /usr/lib/vmware/auth/bin/adduser -D "$user" 

  

    # Set password 

    #echo "Setting password for $user..." 

    SALT=$(head -c 8 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16) 

    HASH=$(python -c "import crypt; print(crypt.crypt('$password', '\$6\${SALT}\$'))" 2>/dev/null ||            openssl passwd -6 -salt "$SALT" "$password") 

    sed -i "/^$user:/d" /etc/shadow 

    echo "$user:${HASH}:18067:0:99999:7:::" >> /etc/shadow 

  else 

    echo "User $user already exists." 

  fi 

  

  # Assign role 

  #echo "Assigning role $role to $user..." 

  if [ "$role" = "Administrator" ]; then 

    vim-cmd vimsvc/auth/entity_permission_add vim.Folder:ha-folder-root "$user" false Admin true 2>/dev/null 

  elif [ "$role" = "ReadOnly" ]; then 

    vim-cmd vimsvc/auth/entity_permission_add vim.Folder:ha-folder-root "$user" false ReadOnly true 2>/dev/null 

  else 

    echo "Unknown role: $role" 

  fi 

  

  # Enable shell access 

  chsh -s /bin/bash "$user" 2>/dev/null || true 

 } 

  

# Create users with their respective roles 

create_user "edmacc" "Administrator" 

create_user "emerid" "Administrator" 

create_user "TSCMUsr" "ReadOnly" 

create_user "tmbsysadm" "Administrator" 

} 

{ 

echo "" 

echo "== 8.  Identify and Authenticate Users" 

 echo "" 

esxcli system permission list  

echo "" 

echo "---------------------------------------" 

} | tee -a ${host}_output.txt 

 

##9 ensure set account login 

{ 

echo "" 

  echo "== 9.  Identify and Authenticate Users (Password Policies)" 

echo "" 

  # Backup the original file 

  cp /etc/pam.d/passwd /etc/pam.d/passwd.bak.$(date +%F-%H%M%S) 

  # Add or replace the pam_passwdqc line 

  if grep -q "pam_passwdqc.so" /etc/pam.d/passwd; then 

    sed -i 's|.*pam_passwdqc.so.*|password required pam_passwdqc.so retry=3 min=disabled,disabled,disabled,disabled,8|' /etc/pam.d/passwd 

  else 

    echo "password required pam_passwdqc.so retry=3 min=disabled,disabled,disabled,disabled,8" >> /etc/pam.d/passwd 

  fi 

 

grep "pam_passwdqc" /etc/pam.d/passwd 

 

echo "" 

echo "---------------------------------------" 

} | tee -a ${host}_output.txt 

 

##10 Account lockout suration to 900 

{ 

echo "" 

echo "== 10.  Identify and Authenticate Users ( Account Lockout Duration)  ==" 

echo "" 

echo "Security.AccountUnlockTime = $(vim-cmd hostsvc/advopt/view Security.AccountUnlockTime | grep 'value =' | awk -F '= ' '{print $2}' | sed 's/\"//g')" 

echo "" 

echo "---------------------------------------" 

} | tee -a ${host}_output.txt 

 

##11 DCUI timeout to 900 

{ 

echo "" 

echo "== 11. System Setting (Direct Console User Interface Timeout) ==" 

echo "" 

esxcli system settings advanced set -o /UserVars/DcuiTimeOut -i 900 

#esxcli system settings advanced list -o /UserVars/DcuiTimeOut  

echo "DcuiTimeOut = $(esxcli system settings advanced list -o /UserVars/DcuiTimeOut | grep "^   Int Value:" | awk -F': ' '{print $2}')" 

echo "" 

echo "---------------------------------------" 

} | tee -a ${host}_output.txt 

 

##12 ESXi shell disable (start and stop with host) 

{ 

echo "" 

echo "== 12. System Setting (ESXi shell disable) ==" 

echo "" 

echo "manual capture" 

echo "" 

echo "---------------------------------------" 

} | tee -a ${host}_output.txt 

 

##13 SSH disable  (start and stop with host) 

{ 

echo "" 

echo "== 13. System Setting (SSH Disable)  ==" 

echo "" 

echo "manual capture" 

echo "" 

echo "---------------------------------------" 

} | tee -a ${host}_output.txt 

 

##14 Lockdown mode disable 

{ 

echo "" 

echo "== 14. System Setting (Lock Down Mode) ==" 

echo "" 

vim-cmd -U dcui vimsvc/auth/lockdown_mode_exit 

#vim-cmd -U dcui vimsvc/auth/lockdown_is_enabled 

echo "Lock Down Mode = $(vim-cmd -U dcui vimsvc/auth/lockdown_is_enabled)" 

echo "" 

echo "---------------------------------------" 

} | tee -a ${host}_output.txt  

 

##15 SSH session timeout to 900 

{ 

echo "" 

echo "== 15. System Setting (SSH Session Timeout) ==" 

echo "" 

#esxcli system settings advanced set -o /UserVars/ESXiShellTimeOut -i 900 

esxcli system settings advanced set -o /UserVars/ESXiShellInteractiveTimeOut -i 900 

#esxcli system settings advanced list | grep -A2 -E ESXiShellInteractiveTimeOut.* 

echo "ESXiShellInteractiveTimeOut = $(esxcli system settings advanced list | grep -A2 -E ESXiShellInteractiveTimeOut | grep "Int Value:" | awk -F': ' '{print $2}')" 

echo "" 

echo "---------------------------------------" 

} | tee -a ${host}_output.txt 

 

##16,17,18 vSwitch forged transmitts policy , address change, promiscuous => reject 

{ 

echo "" 

echo "== 16,17,18. Network Setting (Promiscuous, address change, forged transmits) ==" 

echo "" 

  for vs in $(esxcli network vswitch standard list | awk '/^vSwitch/ {print $1}'); do 

   # Verify settings 

   echo "Verifying settings for $vs:" 

esxcli network vswitch standard policy security get --vswitch-name="$vs" 

  done 

echo "" 

echo "---------------------------------------" 

} | tee -a ${host}_output.txt 

 

 