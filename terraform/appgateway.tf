resource "azurerm_web_application_firewall_policy" "waf" {
  name                = local.names.waf_policy
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  tags                = var.tags

  policy_settings {
    enabled = true
    mode    = "Detection" # switch to Prevention once tuned
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }
}

# Public IP is required by App Gateway v2 for the control plane; no listener
# uses it, so the application has NO public entry point.
resource "azurerm_public_ip" "appgw" {
  name                = local.names.appgw_pip
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags

  lifecycle {
    ignore_changes = [ip_tags, zones]
  }
}

locals {
  agw = {
    gw_ipcfg       = "gwipcfg"
    fe_private     = "feprivate"
    fe_public      = "fepublic"
    fe_port_https  = "port443"
    fe_pool        = "frontend-pool"
    be_pool        = "backend-pool"
    fe_http        = "frontend-https"
    be_http        = "backend-https"
    fe_probe       = "frontend-health"
    be_probe       = "backend-health"
    listener_https = "https-private"
    ssl_cert       = "netops-tls"
    path_map       = "pathmap"
    routing_rule   = "path-routing"
  }
}

resource "azurerm_application_gateway" "agw" {
  name                = local.names.appgw
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  firewall_policy_id  = azurerm_web_application_firewall_policy.waf.id
  tags                = var.tags

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 1
  }

  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.agw.id]
  }

  gateway_ip_configuration {
    name      = local.agw.gw_ipcfg
    subnet_id = azurerm_subnet.appgw.id
  }

  frontend_port {
    name = local.agw.fe_port_https
    port = 443
  }

  frontend_ip_configuration {
    name                          = local.agw.fe_private
    subnet_id                     = azurerm_subnet.appgw.id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.appgw_private_ip
  }

  frontend_ip_configuration {
    name                 = local.agw.fe_public
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  ssl_certificate {
    name     = local.agw.ssl_cert
    data     = var.tls_pfx_base64
    password = var.tls_pfx_password
  }

  backend_address_pool {
    name  = local.agw.fe_pool
    fqdns = [azurerm_linux_web_app.frontend.default_hostname]
  }

  backend_address_pool {
    name  = local.agw.be_pool
    fqdns = [azurerm_linux_web_app.app.default_hostname]
  }

  probe {
    name                                      = local.agw.fe_probe
    protocol                                  = "Https"
    path                                      = "/"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true
    match {
      status_code = ["200-399"]
    }
  }

  probe {
    name                                      = local.agw.be_probe
    protocol                                  = "Https"
    path                                      = "/api/v1/health"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true
    match {
      status_code = ["200-399"]
    }
  }

  backend_http_settings {
    name                                = local.agw.fe_http
    cookie_based_affinity               = "Disabled"
    port                                = 443
    protocol                            = "Https"
    request_timeout                     = 30
    pick_host_name_from_backend_address = true
    probe_name                          = local.agw.fe_probe
  }

  backend_http_settings {
    name                                = local.agw.be_http
    cookie_based_affinity               = "Disabled"
    port                                = 443
    protocol                            = "Https"
    request_timeout                     = 30
    pick_host_name_from_backend_address = true
    probe_name                          = local.agw.be_probe
  }

  http_listener {
    name                           = local.agw.listener_https
    frontend_ip_configuration_name = local.agw.fe_private
    frontend_port_name             = local.agw.fe_port_https
    protocol                       = "Https"
    ssl_certificate_name           = local.agw.ssl_cert
  }

  url_path_map {
    name                               = local.agw.path_map
    default_backend_address_pool_name  = local.agw.fe_pool
    default_backend_http_settings_name = local.agw.fe_http

    path_rule {
      name                       = "api"
      paths                      = ["/api/*"]
      backend_address_pool_name  = local.agw.be_pool
      backend_http_settings_name = local.agw.be_http
    }
  }

  request_routing_rule {
    name               = local.agw.routing_rule
    rule_type          = "PathBasedRouting"
    priority           = 100
    http_listener_name = local.agw.listener_https
    url_path_map_name  = local.agw.path_map
  }

  depends_on = [
    azurerm_private_endpoint.app,
    azurerm_private_endpoint.frontend,
  ]
}
