resource "random_password" "jwt" {
  length  = 48
  special = false
}

resource "azurerm_service_plan" "plan" {
  name                = local.names.plan
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  os_type             = "Linux"
  sku_name            = "P1v2"
  tags                = var.tags
}

resource "azurerm_linux_web_app" "app" {
  name                            = local.names.app
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = var.location
  service_plan_id                 = azurerm_service_plan.plan.id
  https_only                      = true
  public_network_access_enabled   = false
  virtual_network_subnet_id       = azurerm_subnet.app_integration.id
  key_vault_reference_identity_id = azurerm_user_assigned_identity.app.id
  tags                            = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app.id]
  }

  site_config {
    always_on              = true
    health_check_path      = "/api/v1/health"
    vnet_route_all_enabled = true

    container_registry_use_managed_identity       = true
    container_registry_managed_identity_client_id = azurerm_user_assigned_identity.app.client_id

    application_stack {
      docker_image_name   = "netops-backend:latest"
      docker_registry_url = "https://${azurerm_container_registry.acr.login_server}"
    }
  }

  app_settings = {
    WEBSITES_PORT = "8000"

    JWT_SECRET      = random_password.jwt.result
    ALLOWED_ORIGINS = ""      # single-origin behind App Gateway; no CORS needed
    SERVE_STATIC    = "false" # backend serves only /api; frontend is a separate service
    DEMO_USER       = var.demo_user
    DEMO_PASS       = var.demo_password

    DB_HOST     = azurerm_postgresql_flexible_server.pg.fqdn
    DB_USER     = var.pg_admin_login
    DB_NAME     = azurerm_postgresql_flexible_server_database.appdb.name
    DB_PASSWORD = local.pg_password
  }

  depends_on = [
    azurerm_role_assignment.acr_pull,
    azurerm_role_assignment.kv_app_secrets,
  ]

  lifecycle {
    # deploy.ps1 pushes the image tag after apply; ignore drift on the tag.
    ignore_changes = [site_config[0].application_stack[0].docker_image_name]
  }
}

# --- Private endpoint (inbound) for the App Service ---
resource "azurerm_private_endpoint" "app" {
  name                = "pe-app-${var.prefix}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-app"
    private_connection_resource_id = azurerm_linux_web_app.app.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "web"
    private_dns_zone_ids = [azurerm_private_dns_zone.zones["web"].id]
  }
}

# --- Frontend App Service (stand-in for the Static Web App) ---
resource "azurerm_linux_web_app" "frontend" {
  name                          = local.names.frontend
  resource_group_name           = azurerm_resource_group.rg.name
  location                      = var.location
  service_plan_id               = azurerm_service_plan.plan.id
  https_only                    = true
  public_network_access_enabled = false
  virtual_network_subnet_id     = azurerm_subnet.app_integration.id
  tags                          = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app.id]
  }

  site_config {
    always_on              = true
    health_check_path      = "/"
    vnet_route_all_enabled = true

    container_registry_use_managed_identity       = true
    container_registry_managed_identity_client_id = azurerm_user_assigned_identity.app.client_id

    application_stack {
      docker_image_name   = "netops-frontend:latest"
      docker_registry_url = "https://${azurerm_container_registry.acr.login_server}"
    }
  }

  app_settings = {
    WEBSITES_PORT = "80"
  }

  depends_on = [azurerm_role_assignment.acr_pull]

  lifecycle {
    ignore_changes = [site_config[0].application_stack[0].docker_image_name]
  }
}

resource "azurerm_private_endpoint" "frontend" {
  name                = "pe-fe-${var.prefix}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-fe"
    private_connection_resource_id = azurerm_linux_web_app.frontend.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "web"
    private_dns_zone_ids = [azurerm_private_dns_zone.zones["web"].id]
  }
}
