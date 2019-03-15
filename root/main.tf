provider "azurerm" {
  version         = "=1.23.0"
  subscription_id = "bec2e345-66d9-4c18-93e0-6e37990e6aec"
}


resource "azurerm_resource_group" "rg" {
  name     = "svcendpoint-core-uks-rg"
  location = "uksouth"
}


resource "azurerm_virtual_network" "vnet" {
  name                = "svcendpoint-core-uks-vnet"
  resource_group_name = "${azurerm_resource_group.rg.name}"
  location            = "${azurerm_resource_group.rg.location}"

  address_space       = ["172.16.0.0/16"]
}


resource "azurerm_network_security_group" "nsg" {
  name                = "svcendpoint-core-uks-nsg"
  resource_group_name = "${azurerm_resource_group.rg.name}"
  location            = "${azurerm_resource_group.rg.location}"
}


resource "azurerm_network_security_rule" "nsg_rule_rdp" {
  name                        = "AllowRdpIn"
  priority                    = "100"
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "3389"
  source_address_prefix       = "94.12.211.79/32"
  destination_address_prefix  = "*"
  resource_group_name         = "${azurerm_resource_group.rg.name}"
  network_security_group_name = "${azurerm_network_security_group.nsg.name}"
}


resource "azurerm_subnet" "snet_vm" {
  name                 = "vm-core-uks-snet"
  resource_group_name  = "${azurerm_resource_group.rg.name}"
  virtual_network_name = "${azurerm_virtual_network.vnet.name}"
  
  address_prefix       = "${cidrsubnet("${azurerm_virtual_network.vnet.address_space[0]}", 8, 0)}"

  network_security_group_id = "${azurerm_network_security_group.nsg.id}"

  service_endpoints    = [
    "Microsoft.Storage",
    "Microsoft.KeyVault"
  ]
}


resource "azurerm_subnet_network_security_group_association" "vm_snet_nsg" {
  network_security_group_id = "${azurerm_network_security_group.nsg.id}"
  subnet_id                 = "${azurerm_subnet.snet_vm.id}"
}


resource "azurerm_key_vault" "kv" {
  name                = "svcendpoint-core-uks-kv"
  resource_group_name = "${azurerm_resource_group.rg.name}"
  location            = "${azurerm_resource_group.rg.location}"
  
  tenant_id           = "761bb317-1083-4165-8980-507300f69cbe"
  
  sku {
    name = "standard"
  }

  access_policy {
    tenant_id = "761bb317-1083-4165-8980-507300f69cbe"
    object_id = "8a589fb7-3539-47fa-b265-12cd55fced9c"

    certificate_permissions = [
      "backup",
      "create",
      "delete",
      "deleteissuers",
      "get",
      "getissuers",
      "import",
      "list",
      "listissuers",
      "managecontacts",
      "manageissuers",
      "purge",
      "recover",
      "restore",
      "setissuers",
      "update"
    ]

    key_permissions = [
      "backup",
      "create",
      "decrypt",
      "delete",
      "encrypt",
      "get",
      "import",
      "list",
      "purge",
      "recover",
      "restore",
      "sign",
      "unwrapkey",
      "update",
      "verify",
      "wrapkey"
    ]
    
    secret_permissions = [
      "backup",
      "delete",
      "get",
      "list",
      "purge",
      "recover",
      "restore",
      "set"
    ]
  }

  network_acls {
    default_action = "Deny"
    bypass         = "None"
    ip_rules       = ["94.12.211.79/32"]
    virtual_network_subnet_ids = ["${azurerm_subnet.snet_vm.id}"]
  }
}


resource "random_id" "storage_id" {
  byte_length = 4
}


resource "azurerm_storage_account" "storage" {
  name                = "svcendpointuks${random_id.storage_id.dec}"
  resource_group_name = "${azurerm_resource_group.rg.name}"
  location            = "${azurerm_resource_group.rg.location}"

  account_tier             = "Standard"
  account_replication_type = "LRS"

  network_rules {
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = ["${azurerm_subnet.snet_vm.id}"]
    ip_rules                   = ["94.12.211.79"]
  }
}


resource "azurerm_storage_container" "container" {
  name                 = "container1"
  resource_group_name  = "${azurerm_resource_group.rg.name}"
  storage_account_name = "${azurerm_storage_account.storage.name}"  
}


resource "azurerm_public_ip" "pip" {
  name                = "azuksclient1-pip"
  resource_group_name = "${azurerm_resource_group.rg.name}"
  location            = "${azurerm_resource_group.rg.location}"

  allocation_method   = "Dynamic"
}


resource "azurerm_network_interface" "nic" {
  name                = "azuksclient1-nic"
  resource_group_name = "${azurerm_resource_group.rg.name}"
  location            = "${azurerm_resource_group.rg.location}"

  ip_configuration {
    name                          = "IpConfig1"
    subnet_id                     = "${azurerm_subnet.snet_vm.id}"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = "${azurerm_public_ip.pip.id}"
  }
}


resource "random_string" "vm_password" {
  length      = 16
  special     = true
}


resource "azurerm_key_vault_secret" "vm_password" {
  name  = "VmAdminPassword"
  value = "${random_string.vm_password.result}"
  key_vault_id = "${azurerm_key_vault.kv.id}"
}


resource "azurerm_virtual_machine" "vm" {
  name                  = "azuksclient1-vm"
  location              = "${azurerm_resource_group.rg.location}"
  resource_group_name   = "${azurerm_resource_group.rg.name}"

  network_interface_ids = ["${azurerm_network_interface.nic.id}"]
  vm_size               = "Standard_DS1_v2"

  delete_os_disk_on_termination    = true
  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter"
    version   = "latest"
  }

  storage_os_disk {
    name              = "azuksclient1-osdisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "azuksclient1"
    admin_username = "denyer.admin"
    admin_password = "${random_string.vm_password.result}"
  }

  os_profile_windows_config {
    provision_vm_agent        = true
    enable_automatic_upgrades = true
    timezone                  = "GMT Standard Time"
  }
}