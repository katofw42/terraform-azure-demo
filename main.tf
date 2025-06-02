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

# Create Network Interfaces
resource "azurerm_network_interface" "zone1" {
  count               = 1
  name                = "nic-z1-${count.index}"
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
  count               = 1
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



# Associate VMs to Backend Pool
resource "azurerm_network_interface_backend_address_pool_association" "zone1" {
  count                   = 1
  network_interface_id    = azurerm_network_interface.zone1[count.index].id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.main.id
}

# Output

output "vm_admin_password" {
  value     = random_password.vm_password.result
  sensitive = true
}