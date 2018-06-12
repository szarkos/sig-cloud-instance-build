# Kickstart for creating a CentOS 6 Azure VM

# System authorization information
auth --enableshadow --passalgo=sha512

# Use text install
text

# Do not run the Setup Agent on first boot
firstboot --disable

# Keyboard layouts
keyboard us

# System language
lang en_US.UTF-8

# Network information
network --bootproto=dhcp
network --hostname=localhost.localdomain
firewall --enabled --service=ssh

# Use network installation
url --url="http://mirror.centos.org/centos/6/os/x86_64"
repo --name "os" --baseurl="http://mirror.centos.org/centos/6/os/x86_64/" --cost=100
repo --name "updates" --baseurl="http://mirror.centos.org/centos/6/updates/x86_64/" --cost=100
repo --name "extras" --baseurl="http://mirror.centos.org/centos/6/extras/x86_64/" --cost=100

# Root password
rootpw --plaintext "to_be_disabled"

# Enable SELinux
selinux --enforcing

# System services
services --disabled="kdump,cups" --enabled="sshd,waagent,ntpd,dnsmasq,hypervkvpd"

# System timezone
timezone Etc/UTC --isUtc

# Partition clearing information
zerombr
clearpart --all --initlabel
part / --fstype="ext4" --size=1 --grow --asprimary

# System bootloader configuration
bootloader --location=mbr --append="console=ttyS0,115200n8 earlyprintk=ttyS0,115200 rootdelay=300" --timeout=1

# Don't configure X
skipx

# Power down the machine after install
poweroff

%packages
@base
@console-internet
@core
@debugging
@directory-client
@hardware-monitoring
@java-platform
@large-systems
@network-file-system-client
@performance
@perl-runtime
@server-platform
system-config-firewall-base
ntp
dnsmasq
cifs-utils
sudo
python-pyasn1
parted
#WALinuxAgent
-dracut-config-rescue

%end

%post --erroronfail --log=/var/log/anaconda/post-install.log
#!/bin/bash

# Disable the root account
usermod root -p '!!'

# Remove unneeded parameters in grub
sed -i 's/ numa=off//g' /boot/grub/grub.conf
sed -i 's/ rhgb//g' /boot/grub/grub.conf
sed -i 's/ quiet//g' /boot/grub/grub.conf
sed -i 's/ crashkernel=auto//g' /boot/grub/grub.conf

# Set default kernel
cat <<EOL > /etc/sysconfig/kernel
# UPDATEDEFAULT specifies if new-kernel-pkg should make
# new kernels the default
UPDATEDEFAULT=yes

# DEFAULTKERNEL specifies the default kernel package type
DEFAULTKERNEL=kernel
EOL

# Ensure Hyper-V drivers are built into initramfs
echo -e "\nadd_drivers+=\"hv_vmbus hv_netvsc hv_storvsc\"" >> /etc/dracut.conf
kversion=$( rpm -q kernel | sed 's/kernel\-//' )
dracut -v -f "/boot/initramfs-${kversion}.img" "$kversion"

# Import CentOS public key
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-6

# Enable SSH keepalive
sed -i 's/^#\(ClientAliveInterval\).*$/\1 180/g' /etc/ssh/sshd_config

# Configure network
cat << EOF > /etc/sysconfig/network-scripts/ifcfg-eth0
DEVICE=eth0
ONBOOT=yes
BOOTPROTO=dhcp
TYPE=Ethernet
USERCTL=no
PEERDNS=yes
IPV6INIT=no
PERSISTENT_DHCLIENT=yes
EOF

cat << EOF > /etc/sysconfig/network
NETWORKING=yes
NOZEROCONF=yes
HOSTNAME=localhost.localdomain
EOF

# Disable persistent net rules
rm -f /etc/udev/rules.d/70-persistent-net.rules 2>/dev/null
ln -s /dev/null /etc/udev/rules.d/75-persistent-net-generator.rules

# Change dhcp client retry/timeouts to resolve #6866
cat  >> /etc/dhcp/dhclient.conf << EOF

timeout 300;
retry 60;
EOF

# Blacklist the nouveau driver as it is incompatible
# with Azure GPU instances.
cat << EOF > /etc/modprobe.d/blacklist-nouveau.conf
blacklist nouveau
options nouveau modeset=0
EOF

# TEMPORARY - Install the Azure Linux agent
curl -so /root/WALinuxAgent-2.2.18-1.el6.noarch.rpm http://olcentgbl.trafficmanager.net/openlogic/6/openlogic/x86_64/RPMS/WALinuxAgent-2.2.18-1.el6.noarch.rpm
rpm --nosignature -i /root/WALinuxAgent-2.2.18-1.el6.noarch.rpm
rm -f /root/WALinuxAgent-2.2.18-1.el6.noarch.rpm
chkconfig waagent on

# Modify yum, clean cache
echo "http_caching=packages" >> /etc/yum.conf
yum clean all

%end
