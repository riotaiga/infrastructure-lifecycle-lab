Vagrant.configure("2") do |config|
    config.vm.box = "bento/ubuntu-24.04"
    config.vm.box_version = "202510.26.0"

    # Disable Vagrant's default folder sync
    config.vm.synced_folder ".", "/vagrant", disabled: true

  # Target Node 1
  config.vm.define "node1" do |node1|
    node1.vm.hostname = "node1"
    node1.vm.network "private_network",
      ip: "192.168.56.251"

    node1.vm.provider "virtualbox" do |vb|
      vb.memory = 1024
      vb.cpus = 1
      vb.gui = false
    end

    node1.vm.provision "shell", path: "provision/target-node.sh"
  end

  # Target Node 2
  config.vm.define "node2" do |node2|
    node2.vm.hostname = "node2"
    node2.vm.network "private_network",
      ip: "192.168.56.252"
    
    node2.vm.provider "virtualbox" do |vb|
      vb.memory = 1024
      vb.cpus = 1
      vb.gui = false
    end

    node2.vm.provision "shell", path: "provision/target-node.sh"
  end 

  # Control Node
  config.vm.define "control" do |control|
    control.vm.hostname = "control"

      # Management network used for node1 and node2 
      control.vm.network "private_network",
        ip: "192.168.56.250"

      # Isolated PXE LAN.  The control node is the only DHCP server on it.
      control.vm.network "private_network",
        ip: "10.20.30.1",
        virtualbox__intnet: "pxe-lan"

    control.vm.provider "virtualbox" do |vb|
      vb.memory = 8192
      # note to myself: four vCPUs avoid the VirtualBox guest kernel lockup seen with four.
      # 8 GB RAM remains available for the llama3.2:3b model.
      vb.cpus = 4
      vb.gui = false
    end

    # Make sure the current host public key is copied to control node (for seemless access)
    # Find your key (works on Windows..)
    key_file = ["#{Dir.home}/.ssh/id_ed25519.pub", "#{Dir.home}/.ssh/id_rsa.pub"].find { |f| File.file?(f) }

    if key_file
      # Read the key content
      pub_key = File.read(key_file).strip

    # Run commands inside the VM to add it
      config.vm.provision "shell", privileged: false, inline: <<-SHELL
        mkdir -p /home/vagrant/.ssh
        echo "#{pub_key}" >> /home/vagrant/.ssh/authorized_keys
        chmod 700 /home/vagrant/.ssh
        chmod 600 /home/vagrant/.ssh/authorized_keys
      SHELL
    end

    # Setup SSH key and send public key to other hosts
    control.vm.provision "shell", 
      path: "provision/control-node.sh"

    # copy ansible folder onto the control node, which acts as like rsync andn scp.
    control.vm.provision "file", 
      source: "./ansible", 
      destination: "/home/vagrant/ansible"

    # Copy PXE configuration before installing and configuring its services.
    control.vm.provision "shell", 
      inline: "mkdir -p /opt/pxe", 
      privileged: true

    control.vm.provision "file", 
      source: "./pxe", 
      destination: "/tmp/pxe"

    # (review) must move the tmp to opt to have root privileges..
    control.vm.provision "shell", 
      inline: "cp -a /tmp/pxe/. /opt/pxe/", 
      privileged: true

    control.vm.provision "shell", 
      inline: "ls -R /opt/pxe",
      privileged: true

    # create autoinstall file, it needs to be available through HTTP in order to set up Ubuntu server 
    control.vm.provision "shell", 
      inline: "mkdir -p /var/www/html/autoinstall", 
      privileged: true

    control.vm.provision "shell", 
      inline: "cp -a /opt/pxe/autoinstall/. /var/www/html/autoinstall/", 
      privileged: true

    # Publish control's SSH public key for PXE clients during autoinstall.
    control.vm.provision "shell",
      inline: "cp /home/vagrant/.ssh/id_ed25519.pub /var/www/html/autoinstall/control.pub && 
               chmod 644 /var/www/html/autoinstall/control.pub",
      privileged: true

    # Configure DHCP/TFTP on the isolated PXE LAN.
    control.vm.provision "shell", 
      path: "provision/setup-pxe.sh"

    # NAT/route PXE LAN client traffic through control for internet access.
    control.vm.provision "shell",
      path: "provision/setup-pxe-gateway.sh"

    # Install PXE registration service for the clients 
    # The purpose is to obtain PXE server MAC address 
    control.vm.provision "file",
      source: "./provision/pxe-registration.py",
      destination: "/tmp/pxe/pxe-registration.py"

    control.vm.provision "shell",
      inline: "cp /tmp/pxe/pxe-registration.py /opt/pxe/pxe-registration.py",
      privileged: true

    control.vm.provision "file",
      source: "./provision/pxe-registration.service",
      destination: "/tmp/pxe-registration.service"

    control.vm.provision "shell",
      inline: "cp /tmp/pxe-registration.service /etc/systemd/system/pxe-registration.service",
      privileged: true

    control.vm.provision "shell",
      inline: <<-SHELL
      chmod +x /opt/pxe/pxe-registration.py
      mkdir -p /var/lib/pxe/clients
      touch /etc/dnsmasq.d/pxe-installed.conf
      systemctl daemon-reload
      systemctl enable --now pxe-registration.service
      echo "=== PXE Registration Service is Ready ==="
    SHELL

    # remove pxe folder from tmp folder
    control.vm.provision "shell", inline: "rm -rf /tmp/pxe", privileged: true

  
    # Install ollama (testing)
    #control.vm.provision "shell", path: "provision/setup-ollama.sh"

    # Run a connectivity check from the control node after Ollama is ready.
    #control.vm.provision "shell", path: "provision/verify-ollama.sh"
  end

  config.vm.define "pxe-client-01" do |pxe_client|
    pxe_client.vm.hostname = "pxe-client"

    # Empty disk only — OS is installed over PXE, not from a Vagrant box image.
    pxe_client.vm.box = "pace/empty"
    pxe_client.vm.box_version = "0.1.0" 
    pxe_client.vm.box_check_update = false

    # No SSH agent on a blank VM; skip the usual boot/SSH readiness wait.
    pxe_client.vm.communicator = "dummy"
    pxe_client.vm.boot_timeout = 900

    # Dedicated visual PXE test client. Its operating system is installed from
    # the PXE server, so Vagrant does not connect to or provision this VM.
    pxe_client.vm.provider "virtualbox" do |vb|
      # This sets the name you see in the VirtualBox GUI
      vb.name = "pxe-client-01"
      vb.memory = 16384
      vb.cpus = 2      
      vb.gui = true

      vb.customize [
        "modifyvm", :id,
        "--nic1", "intnet",
        "--intnet1", "pxe-lan",
        "--nictype1", "82540EM",
        "--cableconnected1", "on"
      ]

      vb.customize [
        "modifyvm", :id,
        "--nic2", "none",
      ]

      vb.customize [
        "modifyvm", :id,
        "--nic3", "none"
      ]   

      vb.customize [
        "modifyvm", :id,
        "--nic4", "none"
      ]

      # Legacy BIOS required for pxelinux.0 / dnsmasq PXE boot (UEFI cannot use this stack).
      vb.customize ["modifyvm", :id, "--firmware", "bios"]

      # Disk first, network second = PXE used once without registration.
      # Empty disk fails → BIOS tries network → install. After install → disk boots.
      vb.customize ["modifyvm", :id, "--boot1", "disk"]
      vb.customize ["modifyvm", :id, "--boot2", "net"]
      vb.customize ["modifyvm", :id, "--boot3", "none"]
      vb.customize ["modifyvm", :id, "--boot4", "none"]
    end
  end
end