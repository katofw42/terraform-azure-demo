# Configure the Azure Provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.0"
    }
  }
}

provider "azurerm" {
  subscription_id = "9eb32675-efcd-4315-baf1-f58c4adbda67"
  # tenant_id       = var.provider_credentials.tenant_id
  # client_id       = var.provider_credentials.sp_client_id
  # client_secret   = var.provider_credentials.sp_client_secret
  features {}
}

# Generate random password
resource "random_password" "vm_password" {
  length  = 16
  special = true
}

# Create a resource group
resource "azurerm_resource_group" "main" {
  name     = "rg-webapp"
  location = "Japan East"
}

# Create a virtual network
resource "azurerm_virtual_network" "main" {
  name                = "vnet-webapp"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

# Create subnet
resource "azurerm_subnet" "main" {
  name                 = "subnet-main"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Create public IP for Load Balancer
resource "azurerm_public_ip" "lb" {
  name                = "pip-lb"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Create Load Balancer
resource "azurerm_lb" "main" {
  name                = "lb-main"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "frontend"
    public_ip_address_id = azurerm_public_ip.lb.id
  }
}

# Create Backend Pool
resource "azurerm_lb_backend_address_pool" "main" {
  loadbalancer_id = azurerm_lb.main.id
  name            = "backend-pool"
}

# Create Network Interfaces
resource "azurerm_network_interface" "zone1" {
  count               = 2
  name                = "nic-z1-${count.index}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface" "zone2" {
  count               = 2
  name                = "nic-z2-${count.index}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Create Virtual Machines Zone 1
resource "azurerm_linux_virtual_machine" "zone1" {
  count               = 2
  name                = "vm-z1-${count.index}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  zone                = "1"
  size                = "Standard_B1s"
  admin_username      = "adminuser"
  admin_password      = random_password.vm_password.result

  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.zone1[count.index].id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}

# Create Virtual Machines Zone 2
resource "azurerm_linux_virtual_machine" "zone2" {
  count               = 2
  name                = "vm-z2-${count.index}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  zone                = "2"
  size                = "Standard_B1s"
  admin_username      = "adminuser"
  admin_password      = random_password.vm_password.result

  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.zone2[count.index].id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}

# Associate VMs to Backend Pool
resource "azurerm_network_interface_backend_address_pool_association" "zone1" {
  count                   = 2
  network_interface_id    = azurerm_network_interface.zone1[count.index].id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.main.id
}

resource "azurerm_network_interface_backend_address_pool_association" "zone2" {
  count                   = 2
  network_interface_id    = azurerm_network_interface.zone2[count.index].id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.main.id
}

# Output
output "load_balancer_ip" {
  value = azurerm_public_ip.lb.ip_address
}

output "vm_admin_password" {
  value     = random_password.vm_password.result
  sensitive = true
}