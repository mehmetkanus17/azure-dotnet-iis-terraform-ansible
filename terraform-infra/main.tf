# main.tf
resource "azurerm_resource_group" "rg" {
  name     = var.rg_name
  location = var.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = "case-${terraform.workspace}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "case-${terraform.workspace}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Public IP (postgresql-db ve windows için)
resource "azurerm_public_ip" "public_ip" {
  for_each            = toset(var.vm_names)
  name                = "pip-${each.key}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# NSG - Linux (PostgreSQL)
resource "azurerm_network_security_group" "nsg_linux" {
  name                = "nsg-linux"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*" #var.control_public_ip
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-Postgres"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# NSG - Windows (IIS)
resource "azurerm_network_security_group" "nsg_windows" {
  name                = "nsg-windows"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "Allow-RDP"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*" #var.control_public_ip
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTPS"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

# WinRM over HTTPS (Prod - 5986) - sadece Ansible kontrol makinesine izin verir
security_rule {
  name                       = "Allow-WinRM-HTTP"
  priority                   = 1004
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "5985"
  source_address_prefix      = "*" #var.control_public_ip
  destination_address_prefix = "*"
  description                = "Allow secure with HTTP"
}

security_rule {
  name                       = "Allow-WinRM-HTTPS"
  priority                   = 1005
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "5986"
  source_address_prefix      = "*" #var.control_public_ip
  destination_address_prefix = "*"
  description                = "Allow secure with HTTPS"
}
}

resource "azurerm_network_interface" "nic" {
  for_each            = toset(var.vm_names)
  name                = "nic-${each.key}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip[each.key].id
  }
}

resource "azurerm_network_interface_security_group_association" "nsg_assoc" {
  for_each = toset(var.vm_names)

  network_interface_id = azurerm_network_interface.nic[each.key].id

  network_security_group_id = (
    each.key == "postgresql-db" ? azurerm_network_security_group.nsg_linux.id :
    azurerm_network_security_group.nsg_windows.id
  )
}

# Linux VM (PostgreSQL)
resource "azurerm_linux_virtual_machine" "vm_linux" {
  name                = "postgresql-db"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = var.linux_vm_size
  admin_username      = var.admin_username
  network_interface_ids = [azurerm_network_interface.nic["postgresql-db"].id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }

  os_disk {
    name                 = "disk-postgresql-db"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(<<-EOF
#!/bin/bash
set -e

# Log dosyası
LOG_FILE="/var/log/postgresql-setup.log"
exec > >(tee -a $LOG_FILE) 2>&1

echo "=== PostgreSQL Setup Started at $(date) ==="

# Paket güncellemeleri
echo "Updating packages..."
apt-get update
apt-get upgrade -y

# PostgreSQL kurulumu 
echo "Installing PostgreSQL..."
apt-get install -y postgresql postgresql-contrib

# PostgreSQL'in başlamasını bekle
echo "Waiting for PostgreSQL to start..."
sleep 5
systemctl enable postgresql
systemctl start postgresql
sleep 3

# Veritabanı ve kullanıcı oluştur
echo "Creating database and user..."
sudo -u postgres psql -c "CREATE DATABASE xxxxxxx;"
sudo -u postgres psql -c "CREATE USER xxxxxxx WITH ENCRYPTED PASSWORD 'xxxxxxx';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE xxxxxxx TO xxxxxxx;"
sudo -u postgres psql -d xxxxxxx -c "GRANT ALL ON SCHEMA public TO xxxxxxx;"

# PostgreSQL yapılandırması - listen_addresses
echo "Configuring listen_addresses..."
sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /etc/postgresql/14/main/postgresql.conf

# pg_hba.conf - Yerel bağlantılar için md5 (localhost erişimi)
echo "Configuring local authentication..."
sudo sed -i 's/^local\s\+all\s\+all\s\+peer$/local   all             all                                     md5/' /etc/postgresql/14/main/pg_hba.conf

# pg_hba.conf - Uzaktan erişim için md5
echo "Configuring remote access..."
echo "host    all             all             0.0.0.0/0               md5" | sudo tee -a /etc/postgresql/14/main/pg_hba.conf

# PostgreSQL'i yeniden başlat
echo "Restarting PostgreSQL..."
systemctl restart postgresql
sleep 3

# Bağlantı kontrolü
echo "Testing PostgreSQL connection..."
sudo -u postgres psql -c "SELECT version();"

# Port kontrolü
echo "Checking PostgreSQL port..."
netstat -tulpn | grep 5432 || ss -tulpn | grep 5432

echo "=== PostgreSQL Setup Completed at $(date) ==="

EOF
  )
}

# Windows VM (IIS)
resource "azurerm_windows_virtual_machine" "vm_windows" {
  name                = "windows-kaynak"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = var.windows_vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  network_interface_ids = [azurerm_network_interface.nic["windows-kaynak"].id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-g2"
    version   = "latest"
  }
}

# WinRM Bootstrap Extension - Inline Script
resource "azurerm_virtual_machine_extension" "bootstrap" {
  name                 = "bootstrap"
  virtual_machine_id   = azurerm_windows_virtual_machine.vm_windows.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  protected_settings = jsonencode({
    commandToExecute = "powershell -ExecutionPolicy Unrestricted -Command \"Enable-PSRemoting -Force; Set-Service WinRM -StartupType Automatic; if (-not (winrm enumerate winrm/config/Listener | findstr HTTP)) { winrm create winrm/config/Listener?Address=*+Transport=HTTP }; Set-Item -Path 'WSMan:\\localhost\\Service\\AllowUnencrypted' -Value $true -Force; Set-Item -Path 'WSMan:\\localhost\\Service\\Auth\\Basic' -Value $true -Force; Set-Item -Path 'WSMan:\\localhost\\Client\\TrustedHosts' -Value '*' -Force; New-NetFirewallRule -DisplayName 'Allow WinRM HTTP' -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -ErrorAction SilentlyContinue; Restart-Service WinRM\""
  })

  depends_on = [azurerm_windows_virtual_machine.vm_windows]
}

# Terraform outputs - Ansible için
output "windows_vm_details" {
  value = {
    vm_name    = azurerm_windows_virtual_machine.vm_windows.name
    public_ip  = azurerm_public_ip.public_ip["windows-kaynak"].ip_address
    private_ip = azurerm_network_interface.nic["windows-kaynak"].private_ip_address
    admin_user = var.admin_username
  }
  description = "Windows VM bilgileri - Ansible inventory için"
}

output "winrm_connection" {
  value = {
    host      = azurerm_public_ip.public_ip["windows-kaynak"].ip_address
    http_port = 5985
    https_port = 5986
    user      = var.admin_username
  }
  description = "WinRM bağlantı bilgileri"
  sensitive   = false
}

output "public_ips" {
  value = {
    for name, pip in azurerm_public_ip.public_ip :
    name => pip.ip_address
  }
}

output "admin_username" {
  value       = var.admin_username
  description = "VM admin kullanıcısı"
}

