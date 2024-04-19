# Terraform manifest for deployment of OpenStack Sunbeam
#
# Copyright (c) 2022 Canonical Ltd.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.
# See the License for the specific language governing permissions and
# limitations under the License.

terraform {
  required_providers {
    juju = {
      source  = "juju/juju"
      version = "= 0.11.0"
    }
  }
}

provider "juju" {}

locals {
  services-with-mysql = ["keystone", "glance", "nova", "horizon", "neutron", "placement", "cinder"]
  grafana-agent-name  = length(juju_application.grafana-agent) > 0 ? juju_application.grafana-agent[0].name : null
}

data "juju_offer" "microceph" {
  count = var.enable-ceph ? 1 : 0
  url   = var.ceph-offer-url
}

resource "juju_model" "sunbeam" {
  name = var.model

  cloud {
    name   = var.cloud
    region = "localhost"
  }

  credential = var.credential
  config     = var.config
}

module "mysql" {
  source                = "./modules/mysql"
  model                 = juju_model.sunbeam.name
  name                  = "mysql"
  channel               = var.mysql-channel
  revision              = var.mysql-revision
  scale                 = var.ha-scale
  many-mysql            = var.many-mysql
  services              = local.services-with-mysql
  resource-configs      = var.mysql-config
  grafana-dashboard-app = local.grafana-agent-name
  metrics-endpoint-app  = local.grafana-agent-name
  logging-app           = local.grafana-agent-name
}

module "rabbitmq" {
  source           = "./modules/rabbitmq"
  model            = juju_model.sunbeam.name
  scale            = var.ha-scale
  channel          = var.rabbitmq-channel
  revision         = var.rabbitmq-revision
  resource-configs = var.rabbitmq-config
}

module "glance" {
  source               = "./modules/openstack-api"
  charm                = "glance-k8s"
  name                 = "glance"
  model                = juju_model.sunbeam.name
  channel              = var.glance-channel == null ? var.openstack-channel : var.glance-channel
  revision             = var.glance-revision
  rabbitmq             = module.rabbitmq.name
  mysql                = module.mysql.name["glance"]
  keystone             = module.keystone.name
  keystone-cacerts     = module.keystone.name
  ingress-internal     = juju_application.traefik.name
  ingress-public       = juju_application.traefik-public.name
  scale                = var.enable-ceph ? var.os-api-scale : 1
  mysql-router-channel = var.mysql-router-channel
  resource-configs = merge(var.glance-config, {
    ceph-osd-replication-count     = var.ceph-osd-replication-count
    enable-telemetry-notifications = var.enable-telemetry
  })
}

module "keystone" {
  source               = "./modules/openstack-api"
  charm                = "keystone-k8s"
  name                 = "keystone"
  model                = juju_model.sunbeam.name
  channel              = var.keystone-channel == null ? var.openstack-channel : var.keystone-channel
  revision             = var.keystone-revision
  rabbitmq             = module.rabbitmq.name
  mysql                = module.mysql.name["keystone"]
  ingress-internal     = juju_application.traefik.name
  ingress-public       = juju_application.traefik-public.name
  scale                = var.os-api-scale
  mysql-router-channel = var.mysql-router-channel
  resource-configs = merge(var.keystone-config, {
    enable-telemetry-notifications = var.enable-telemetry
  })
}

module "nova" {
  source               = "./modules/openstack-api"
  charm                = "nova-k8s"
  name                 = "nova"
  model                = juju_model.sunbeam.name
  channel              = var.nova-channel == null ? var.openstack-channel : var.nova-channel
  revision             = var.nova-revision
  rabbitmq             = module.rabbitmq.name
  mysql                = module.mysql.name["nova"]
  keystone             = module.keystone.name
  keystone-cacerts     = module.keystone.name
  ingress-internal     = ""
  ingress-public       = ""
  scale                = var.os-api-scale
  mysql-router-channel = var.mysql-router-channel
  resource-configs     = var.nova-config
}

resource "juju_integration" "nova-to-ingress-public" {
  model = juju_model.sunbeam.name

  application {
    name     = module.nova.name
    endpoint = "traefik-route-public"
  }

  application {
    name     = juju_application.traefik-public.name
    endpoint = "traefik-route"
  }
}

resource "juju_integration" "nova-to-ingress-internal" {
  model = juju_model.sunbeam.name

  application {
    name     = module.nova.name
    endpoint = "traefik-route-internal"
  }

  application {
    name     = juju_application.traefik.name
    endpoint = "traefik-route"
  }
}

module "horizon" {
  source               = "./modules/openstack-api"
  charm                = "horizon-k8s"
  name                 = "horizon"
  model                = juju_model.sunbeam.name
  channel              = var.horizon-channel == null ? var.openstack-channel : var.horizon-channel
  revision             = var.horizon-revision
  mysql                = module.mysql.name["horizon"]
  keystone-credentials = module.keystone.name
  keystone-cacerts     = module.keystone.name
  ingress-internal     = juju_application.traefik.name
  ingress-public       = juju_application.traefik-public.name
  scale                = var.os-api-scale
  mysql-router-channel = var.mysql-router-channel
  resource-configs = merge(var.horizon-config, {
    plugins = jsonencode(var.horizon-plugins)
  })
}

module "neutron" {
  source               = "./modules/openstack-api"
  charm                = "neutron-k8s"
  name                 = "neutron"
  model                = juju_model.sunbeam.name
  channel              = var.neutron-channel == null ? var.openstack-channel : var.neutron-channel
  revision             = var.neutron-revision
  rabbitmq             = module.rabbitmq.name
  mysql                = module.mysql.name["neutron"]
  keystone             = module.keystone.name
  keystone-cacerts     = module.keystone.name
  ingress-internal     = juju_application.traefik.name
  ingress-public       = juju_application.traefik-public.name
  scale                = var.os-api-scale
  mysql-router-channel = var.mysql-router-channel
  resource-configs     = var.neutron-config
}

module "placement" {
  source               = "./modules/openstack-api"
  charm                = "placement-k8s"
  name                 = "placement"
  model                = juju_model.sunbeam.name
  channel              = var.placement-channel == null ? var.openstack-channel : var.placement-channel
  revision             = var.placement-revision
  mysql                = module.mysql.name["placement"]
  keystone             = module.keystone.name
  keystone-cacerts     = module.keystone.name
  ingress-internal     = juju_application.traefik.name
  ingress-public       = juju_application.traefik-public.name
  scale                = var.os-api-scale
  mysql-router-channel = var.mysql-router-channel
  resource-configs     = var.placement-config
}

resource "juju_application" "traefik" {
  name  = "traefik"
  trust = true
  model = juju_model.sunbeam.name

  charm {
    name     = "traefik-k8s"
    channel  = var.traefik-channel
    revision = var.traefik-revision
  }

  config = var.traefik-config
  units  = var.ingress-scale
}

resource "juju_application" "traefik-public" {
  name  = "traefik-public"
  trust = true
  model = juju_model.sunbeam.name

  charm {
    name     = "traefik-k8s"
    channel  = var.traefik-channel
    revision = var.traefik-revision
  }

  config = var.traefik-config
  units  = var.ingress-scale
}

resource "juju_application" "certificate-authority" {
  name  = "certificate-authority"
  trust = true
  model = juju_model.sunbeam.name

  charm {
    name     = "self-signed-certificates"
    channel  = var.certificate-authority-channel
    revision = var.certificate-authority-revision
  }

  config = merge(var.certificate-authority-config, {
    ca-common-name = "internal-ca"
  })
}

module "ovn" {
  source                 = "./modules/ovn"
  model                  = juju_model.sunbeam.name
  channel                = var.ovn-central-channel == null ? var.ovn-channel : var.ovn-central-channel
  revision               = var.ovn-central-revision
  scale                  = var.ha-scale
  relay                  = true
  relay-scale            = var.os-api-scale
  relay-channel          = var.ovn-relay-channel == null ? var.ovn-channel : var.ovn-relay-channel
  relay-revision         = var.ovn-relay-revision
  ca                     = juju_application.certificate-authority.name
  resource-configs       = var.ovn-central-config
  relay-resource-configs = var.ovn-relay-config
}

# juju integrate ovn-central neutron
resource "juju_integration" "ovn-central-to-neutron" {
  model = juju_model.sunbeam.name

  application {
    name     = module.ovn.name
    endpoint = "ovsdb-cms"
  }

  application {
    name     = module.neutron.name
    endpoint = "ovsdb-cms"
  }
}

# juju integrate neutron vault
resource "juju_integration" "neutron-to-ca" {
  model = juju_model.sunbeam.name

  application {
    name     = module.neutron.name
    endpoint = "certificates"
  }

  application {
    name     = juju_application.certificate-authority.name
    endpoint = "certificates"
  }
}

# juju integrate nova placement
resource "juju_integration" "nova-to-placement" {
  model = juju_model.sunbeam.name

  application {
    name     = module.nova.name
    endpoint = "placement"
  }

  application {
    name     = module.placement.name
    endpoint = "placement"
  }
}

# juju integrate glance microceph
resource "juju_integration" "glance-to-ceph" {
  count = length(data.juju_offer.microceph)
  model = juju_model.sunbeam.name

  application {
    name     = module.glance.name
    endpoint = "ceph"
  }

  application {
    offer_url = data.juju_offer.microceph[count.index].url
  }
}

module "cinder" {
  source               = "./modules/openstack-api"
  charm                = "cinder-k8s"
  name                 = "cinder"
  model                = juju_model.sunbeam.name
  channel              = var.cinder-channel == null ? var.openstack-channel : var.cinder-channel
  revision             = var.cinder-revision
  rabbitmq             = module.rabbitmq.name
  mysql                = module.mysql.name["cinder"]
  keystone             = module.keystone.name
  keystone-cacerts     = module.keystone.name
  ingress-internal     = juju_application.traefik.name
  ingress-public       = juju_application.traefik-public.name
  scale                = var.os-api-scale
  mysql-router-channel = var.mysql-router-channel
  resource-configs     = var.cinder-config
}

module "cinder-ceph" {
  source               = "./modules/openstack-api"
  charm                = "cinder-ceph-k8s"
  name                 = "cinder-ceph"
  model                = juju_model.sunbeam.name
  channel              = var.cinder-ceph-channel == null ? var.openstack-channel : var.cinder-ceph-channel
  revision             = var.cinder-ceph-revision
  rabbitmq             = module.rabbitmq.name
  mysql                = module.mysql.name["cinder"]
  ingress-internal     = ""
  ingress-public       = ""
  scale                = var.ha-scale
  mysql-router-channel = var.mysql-router-channel
  resource-configs = merge(var.cinder-ceph-config, {
    ceph-osd-replication-count     = var.ceph-osd-replication-count
    enable-telemetry-notifications = var.enable-telemetry
  })
}

# juju integrate cinder cinder-ceph
resource "juju_integration" "cinder-to-cinder-ceph" {
  model = juju_model.sunbeam.name

  application {
    name     = module.cinder.name
    endpoint = "storage-backend"
  }

  application {
    name     = module.cinder-ceph.name
    endpoint = "storage-backend"
  }
}

# juju integrate cinder-ceph microceph
resource "juju_integration" "cinder-ceph-to-ceph" {
  count = length(data.juju_offer.microceph)
  model = juju_model.sunbeam.name
  application {
    name     = module.cinder-ceph.name
    endpoint = "ceph"
  }
  application {
    offer_url = data.juju_offer.microceph[count.index].url
  }
}

resource "juju_offer" "ca-offer" {
  model            = juju_model.sunbeam.name
  application_name = juju_application.certificate-authority.name
  endpoint         = "certificates"
}

module "mysql-heat" {
  count                 = var.enable-heat ? (var.many-mysql ? 1 : 0) : 0
  source                = "./modules/mysql"
  model                 = juju_model.sunbeam.name
  name                  = "mysql"
  channel               = var.mysql-channel
  revision              = var.mysql-revision
  scale                 = var.ha-scale
  many-mysql            = var.many-mysql
  services              = ["heat"]
  resource-configs      = var.mysql-config
  grafana-dashboard-app = local.grafana-agent-name
  metrics-endpoint-app  = local.grafana-agent-name
  logging-app           = local.grafana-agent-name
}

module "heat" {
  count                = var.enable-heat ? 1 : 0
  source               = "./modules/openstack-api"
  charm                = "heat-k8s"
  name                 = "heat"
  model                = juju_model.sunbeam.name
  channel              = var.heat-channel == null ? var.openstack-channel : var.heat-channel
  revision             = var.heat-revision
  rabbitmq             = module.rabbitmq.name
  mysql                = var.many-mysql ? module.mysql-heat[0].name["heat"] : "mysql"
  keystone             = module.keystone.name
  keystone-ops         = module.keystone.name
  keystone-cacerts     = module.keystone.name
  ingress-internal     = ""
  ingress-public       = ""
  scale                = var.os-api-scale
  mysql-router-channel = var.mysql-router-channel
  resource-configs     = var.heat-config
}

resource "juju_integration" "heat-to-ingress-public" {
  count = var.enable-heat ? 1 : 0
  model = juju_model.sunbeam.name

  application {
    name     = module.heat[count.index].name
    endpoint = "traefik-route-public"
  }

  application {
    name     = juju_application.traefik-public.name
    endpoint = "traefik-route"
  }
}

resource "juju_integration" "heat-to-ingress-internal" {
  count = var.enable-heat ? 1 : 0
  model = juju_model.sunbeam.name

  application {
    name     = module.heat[count.index].name
    endpoint = "traefik-route-internal"
  }

  application {
    name     = juju_application.traefik.name
    endpoint = "traefik-route"
  }
}

module "mysql-telemetry" {
  count                 = var.enable-telemetry ? (var.many-mysql ? 1 : 0) : 0
  source                = "./modules/mysql"
  model                 = juju_model.sunbeam.name
  name                  = "mysql"
  channel               = var.mysql-channel
  revision              = var.mysql-revision
  scale                 = var.ha-scale
  many-mysql            = var.many-mysql
  services              = ["aodh", "gnocchi"]
  resource-configs      = var.mysql-config
  grafana-dashboard-app = local.grafana-agent-name
  metrics-endpoint-app  = local.grafana-agent-name
  logging-app           = local.grafana-agent-name
}

module "aodh" {
  count                = var.enable-telemetry ? 1 : 0
  source               = "./modules/openstack-api"
  charm                = "aodh-k8s"
  name                 = "aodh"
  model                = juju_model.sunbeam.name
  channel              = var.aodh-channel == null ? var.openstack-channel : var.aodh-channel
  revision             = var.aodh-revision
  rabbitmq             = module.rabbitmq.name
  mysql                = var.many-mysql ? module.mysql-telemetry[0].name["aodh"] : "mysql"
  keystone             = module.keystone.name
  keystone-cacerts     = module.keystone.name
  ingress-internal     = juju_application.traefik.name
  ingress-public       = juju_application.traefik-public.name
  scale                = var.os-api-scale
  mysql-router-channel = var.mysql-router-channel
  resource-configs     = var.aodh-config
}

module "gnocchi" {
  count                = var.enable-telemetry ? 1 : 0
  source               = "./modules/openstack-api"
  charm                = "gnocchi-k8s"
  name                 = "gnocchi"
  model                = juju_model.sunbeam.name
  channel              = var.gnocchi-channel == null ? var.openstack-channel : var.gnocchi-channel
  revision             = var.gnocchi-revision
  mysql                = var.many-mysql ? module.mysql-telemetry[0].name["gnocchi"] : "mysql"
  keystone             = module.keystone.name
  keystone-cacerts     = module.keystone.name
  ingress-internal     = juju_application.traefik.name
  ingress-public       = juju_application.traefik-public.name
  scale                = var.os-api-scale
  mysql-router-channel = var.mysql-router-channel
  resource-configs = merge(var.gnocchi-config, {
    ceph-osd-replication-count = var.ceph-osd-replication-count
  })
}

# juju integrate gnocchi microceph
resource "juju_integration" "gnocchi-to-ceph" {
  count = var.enable-telemetry ? length(data.juju_offer.microceph) : 0
  model = juju_model.sunbeam.name
  application {
    name     = module.gnocchi[count.index].name
    endpoint = "ceph"
  }
  application {
    offer_url = data.juju_offer.microceph[count.index].url
  }
}

resource "juju_application" "ceilometer" {
  count = var.enable-telemetry ? 1 : 0
  name  = "ceilometer"
  model = juju_model.sunbeam.name

  charm {
    name     = "ceilometer-k8s"
    channel  = var.ceilometer-channel == null ? var.openstack-channel : var.ceilometer-channel
    revision = var.ceilometer-revision
  }

  config = var.ceilometer-config
  units  = var.ha-scale
}

resource "juju_integration" "ceilometer-to-rabbitmq" {
  count = var.enable-telemetry ? 1 : 0
  model = juju_model.sunbeam.name

  application {
    name     = juju_application.ceilometer[count.index].name
    endpoint = "amqp"
  }

  application {
    name     = module.rabbitmq.name
    endpoint = "amqp"
  }
}

resource "juju_integration" "ceilometer-to-keystone" {
  count = var.enable-telemetry ? 1 : 0
  model = juju_model.sunbeam.name

  application {
    name     = module.keystone.name
    endpoint = "identity-credentials"
  }

  application {
    name     = juju_application.ceilometer[count.index].name
    endpoint = "identity-credentials"
  }
}

resource "juju_integration" "ceilometer-to-keystone-cacert" {
  count = var.enable-telemetry ? 1 : 0
  model = juju_model.sunbeam.name

  application {
    name     = module.keystone.name
    endpoint = "send-ca-cert"
  }

  application {
    name     = juju_application.ceilometer[count.index].name
    endpoint = "receive-ca-cert"
  }
}

resource "juju_integration" "ceilometer-to-gnocchi" {
  count = var.enable-telemetry ? 1 : 0
  model = juju_model.sunbeam.name

  application {
    name     = module.gnocchi[count.index].name
    endpoint = "gnocchi-service"
  }

  application {
    name     = juju_application.ceilometer[count.index].name
    endpoint = "gnocchi-db"
  }
}

resource "juju_offer" "ceilometer-offer" {
  count            = var.enable-telemetry ? 1 : 0
  model            = juju_model.sunbeam.name
  application_name = juju_application.ceilometer[count.index].name
  endpoint         = "ceilometer-service"
}

resource "juju_application" "openstack-exporter" {
  count = var.enable-telemetry ? 1 : 0
  name  = "openstack-exporter"
  model = juju_model.sunbeam.name

  charm {
    name     = "openstack-exporter-k8s"
    channel  = var.openstack-exporter-channel == null ? var.openstack-channel : var.openstack-exporter-channel
    revision = var.openstack-exporter-revision
  }

  config = var.openstack-exporter-config
  units  = 1
}

resource "juju_integration" "openstack-exporter-to-keystone" {
  count = var.enable-telemetry ? 1 : 0
  model = juju_model.sunbeam.name

  application {
    name     = module.keystone.name
    endpoint = "identity-ops"
  }

  application {
    name     = juju_application.openstack-exporter[count.index].name
    endpoint = "identity-ops"
  }
}

resource "juju_integration" "openstack-exporter-to-keystone-cacert" {
  count = var.enable-telemetry ? 1 : 0
  model = juju_model.sunbeam.name

  application {
    name     = module.keystone.name
    endpoint = "send-ca-cert"
  }

  application {
    name     = juju_application.openstack-exporter[count.index].name
    endpoint = "receive-ca-cert"
  }
}

resource "juju_integration" "openstack-exporter-to-metrics-endpoint" {
  count = (var.enable-telemetry && var.enable-observability) ? 1 : 0
  model = juju_model.sunbeam.name

  application {
    name     = juju_application.openstack-exporter[count.index].name
    endpoint = "metrics-endpoint"
  }

  application {
    name     = juju_application.grafana-agent[count.index].name
    endpoint = "metrics-endpoint"
  }
}

resource "juju_integration" "openstack-exporter-to-grafana-dashboard" {
  count = (var.enable-telemetry && var.enable-observability) ? 1 : 0
  model = juju_model.sunbeam.name

  application {
    name     = juju_application.openstack-exporter[count.index].name
    endpoint = "grafana-dashboard"
  }

  application {
    name     = juju_application.grafana-agent[count.index].name
    endpoint = "grafana-dashboards-consumer"
  }
}

module "mysql-octavia" {
  count                 = var.enable-octavia ? (var.many-mysql ? 1 : 0) : 0
  source                = "./modules/mysql"
  model                 = juju_model.sunbeam.name
  name                  = "mysql"
  channel               = var.mysql-channel
  revision              = var.mysql-revision
  scale                 = var.ha-scale
  many-mysql            = var.many-mysql
  services              = ["octavia"]
  resource-configs      = var.mysql-config
  grafana-dashboard-app = local.grafana-agent-name
  metrics-endpoint-app  = local.grafana-agent-name
  logging-app           = local.grafana-agent-name
}

module "octavia" {
  count                = var.enable-octavia ? 1 : 0
  source               = "./modules/openstack-api"
  charm                = "octavia-k8s"
  name                 = "octavia"
  model                = juju_model.sunbeam.name
  channel              = var.octavia-channel == null ? var.openstack-channel : var.octavia-channel
  revision             = var.octavia-revision
  mysql                = var.many-mysql ? module.mysql-octavia[0].name["octavia"] : "mysql"
  keystone             = module.keystone.name
  keystone-ops         = module.keystone.name
  keystone-cacerts     = module.keystone.name
  ingress-internal     = juju_application.traefik.name
  ingress-public       = juju_application.traefik-public.name
  scale                = var.os-api-scale
  mysql-router-channel = var.mysql-router-channel
  resource-configs     = var.octavia-config
}

# juju integrate ovn-central octavia
resource "juju_integration" "ovn-central-to-octavia" {
  count = var.enable-octavia ? 1 : 0
  model = juju_model.sunbeam.name

  application {
    name     = module.ovn.name
    endpoint = "ovsdb-cms"
  }

  application {
    name     = module.octavia[count.index].name
    endpoint = "ovsdb-cms"
  }
}

# juju integrate octavia certificates
resource "juju_integration" "octavia-to-ca" {
  count = var.enable-octavia ? 1 : 0
  model = juju_model.sunbeam.name

  application {
    name     = module.octavia[count.index].name
    endpoint = "certificates"
  }

  application {
    name     = juju_application.certificate-authority.name
    endpoint = "certificates"
  }
}

resource "juju_application" "bind" {
  count = var.enable-designate ? 1 : 0
  name  = "bind"
  model = juju_model.sunbeam.name

  charm {
    name     = "designate-bind-k8s"
    channel  = var.bind-channel
    revision = var.bind-revision
  }

  config = var.bind-config
  units  = var.ha-scale
}

module "mysql-designate" {
  count                 = var.enable-designate ? (var.many-mysql ? 1 : 0) : 0
  source                = "./modules/mysql"
  model                 = juju_model.sunbeam.name
  name                  = "mysql"
  channel               = var.mysql-channel
  revision              = var.mysql-revision
  scale                 = var.ha-scale
  many-mysql            = var.many-mysql
  services              = ["designate"]
  resource-configs      = var.mysql-config
  grafana-dashboard-app = local.grafana-agent-name
  metrics-endpoint-app  = local.grafana-agent-name
  logging-app           = local.grafana-agent-name
}

module "designate" {
  count                = var.enable-designate ? 1 : 0
  source               = "./modules/openstack-api"
  charm                = "designate-k8s"
  name                 = "designate"
  model                = juju_model.sunbeam.name
  channel              = var.designate-channel
  revision             = var.designate-revision
  rabbitmq             = module.rabbitmq.name
  mysql                = var.many-mysql ? module.mysql-designate[0].name["designate"] : "mysql"
  keystone             = module.keystone.name
  keystone-cacerts     = module.keystone.name
  ingress-internal     = juju_application.traefik.name
  ingress-public       = juju_application.traefik-public.name
  scale                = var.os-api-scale
  mysql-router-channel = var.mysql-router-channel
  resource-configs = merge(var.designate-config, {
    "nameservers" = var.nameservers
  })
}

resource "juju_integration" "designate-to-bind" {
  count = var.enable-designate ? 1 : 0
  model = juju_model.sunbeam.name

  application {
    name     = module.designate[count.index].name
    endpoint = "dns-backend"
  }

  application {
    name     = juju_application.bind[count.index].name
    endpoint = "dns-backend"
  }
}

resource "juju_application" "vault" {
  count = var.enable-vault ? 1 : 0
  model = juju_model.sunbeam.name
  name  = "vault"

  charm {
    name     = "vault-k8s"
    channel  = var.vault-channel
    revision = var.vault-revision
  }

  config = var.vault-config
  units  = 1
}

module "mysql-barbican" {
  count                 = var.enable-barbican ? (var.many-mysql ? 1 : 0) : 0
  source                = "./modules/mysql"
  model                 = juju_model.sunbeam.name
  name                  = "mysql"
  channel               = var.mysql-channel
  revision              = var.mysql-revision
  scale                 = var.ha-scale
  many-mysql            = var.many-mysql
  services              = ["barbican"]
  resource-configs      = var.mysql-config
  grafana-dashboard-app = local.grafana-agent-name
  metrics-endpoint-app  = local.grafana-agent-name
  logging-app           = local.grafana-agent-name
}

module "barbican" {
  count                = var.enable-barbican ? 1 : 0
  source               = "./modules/openstack-api"
  charm                = "barbican-k8s"
  name                 = "barbican"
  model                = juju_model.sunbeam.name
  channel              = var.barbican-channel == null ? var.openstack-channel : var.barbican-channel
  revision             = var.barbican-revision
  rabbitmq             = module.rabbitmq.name
  mysql                = var.many-mysql ? module.mysql-barbican[0].name["barbican"] : "mysql"
  keystone             = module.keystone.name
  keystone-ops         = module.keystone.name
  keystone-cacerts     = module.keystone.name
  ingress-internal     = juju_application.traefik.name
  ingress-public       = juju_application.traefik-public.name
  scale                = var.os-api-scale
  mysql-router-channel = var.mysql-router-channel
  resource-configs     = var.barbican-config
}

resource "juju_integration" "barbican-to-vault" {
  count = (var.enable-barbican && var.enable-vault) ? 1 : 0
  model = juju_model.sunbeam.name

  application {
    name     = module.barbican[count.index].name
    endpoint = "vault-kv"
  }

  application {
    name     = juju_application.vault[count.index].name
    endpoint = "vault-kv"
  }
}

module "mysql-magnum" {
  count                 = var.enable-magnum ? (var.many-mysql ? 1 : 0) : 0
  source                = "./modules/mysql"
  model                 = juju_model.sunbeam.name
  name                  = "mysql"
  channel               = var.mysql-channel
  revision              = var.mysql-revision
  scale                 = var.ha-scale
  many-mysql            = var.many-mysql
  services              = ["magnum"]
  resource-configs      = var.mysql-config
  grafana-dashboard-app = local.grafana-agent-name
  metrics-endpoint-app  = local.grafana-agent-name
  logging-app           = local.grafana-agent-name
}

module "magnum" {
  count                = var.enable-magnum ? 1 : 0
  source               = "./modules/openstack-api"
  charm                = "magnum-k8s"
  name                 = "magnum"
  model                = juju_model.sunbeam.name
  channel              = var.magnum-channel == null ? var.openstack-channel : var.magnum-channel
  revision             = var.magnum-revision
  rabbitmq             = module.rabbitmq.name
  mysql                = var.many-mysql ? module.mysql-magnum[0].name["magnum"] : "mysql"
  keystone             = module.keystone.name
  keystone-ops         = module.keystone.name
  keystone-cacerts     = module.keystone.name
  ingress-internal     = juju_application.traefik.name
  ingress-public       = juju_application.traefik-public.name
  scale                = var.os-api-scale
  mysql-router-channel = var.mysql-router-channel
  resource-configs = merge(var.magnum-config, {
    "cluster-user-trust" = "true"
  })
}

resource "juju_application" "ldap-apps" {
  for_each = var.ldap-apps
  name     = "keystone-ldap-${each.key}"
  model    = var.model

  charm {
    name     = "keystone-ldap-k8s"
    channel  = var.ldap-channel
    revision = var.ldap-revision
  }
  # This is a config charm so 1 unit is enough
  units  = 1
  config = each.value
}

resource "juju_integration" "ldap-to-keystone" {
  for_each = var.ldap-apps
  model    = juju_model.sunbeam.name

  application {
    name     = "keystone-ldap-${each.key}"
    endpoint = "domain-config"
  }

  application {
    name     = module.keystone.name
    endpoint = "domain-config"
  }
}

resource "juju_application" "manual-tls-certificates" {
  count = (var.traefik-to-tls-provider == "manual-tls-certificates") ? 1 : 0
  name  = "manual-tls-certificates"
  model = juju_model.sunbeam.name

  charm {
    name     = "manual-tls-certificates"
    channel  = var.manual-tls-certificates-channel
    revision = var.manual-tls-certificates-revision
  }

  units  = 1 # does not scale
  config = var.manual-tls-certificates-config
}

resource "juju_integration" "traefik-public-to-tls-provider" {
  count = var.enable-tls-for-public-endpoint ? (var.traefik-to-tls-provider == null ? 0 : 1) : 0
  model = juju_model.sunbeam.name

  application {
    name     = juju_application.traefik-public.name
    endpoint = "certificates"
  }

  application {
    name     = var.traefik-to-tls-provider
    endpoint = "certificates"
  }
}

resource "juju_integration" "traefik-to-tls-provider" {
  count = var.enable-tls-for-internal-endpoint ? (var.traefik-to-tls-provider == null ? 0 : 1) : 0
  model = juju_model.sunbeam.name

  application {
    name     = juju_application.traefik.name
    endpoint = "certificates"
  }

  application {
    name     = var.traefik-to-tls-provider
    endpoint = "certificates"
  }
}

resource "juju_application" "tempest" {
  count = var.enable-validation ? 1 : 0
  name  = "tempest"
  model = juju_model.sunbeam.name

  charm {
    name     = "tempest-k8s"
    channel  = var.tempest-channel == null ? var.openstack-channel : var.tempest-channel
    revision = var.tempest-revision
  }

  units  = 1
  config = var.tempest-config
}

resource "juju_integration" "tempest-to-keystone" {
  count = var.enable-validation ? 1 : 0
  model = juju_model.sunbeam.name

  application {
    name     = module.keystone.name
    endpoint = "identity-ops"
  }

  application {
    name     = juju_application.tempest[count.index].name
    endpoint = "identity-ops"
  }
}

resource "juju_integration" "tempest-to-grafana-agent-loki" {
  count = (var.enable-validation && var.enable-observability) ? 1 : 0
  model = juju_model.sunbeam.name

  application {
    name     = juju_application.tempest[count.index].name
    endpoint = "logging"
  }

  application {
    name     = juju_application.grafana-agent[count.index].name
    endpoint = "logging-provider"
  }
}

resource "juju_integration" "tempest-to-grafana-agent-grafana" {
  count = (var.enable-validation && var.enable-observability) ? 1 : 0
  model = juju_model.sunbeam.name

  application {
    name     = juju_application.tempest[count.index].name
    endpoint = "grafana-dashboard"
  }

  application {
    name     = juju_application.grafana-agent[count.index].name
    endpoint = "grafana-dashboards-consumer"
  }
}

resource "juju_application" "grafana-agent" {
  count = var.enable-observability ? 1 : 0
  name  = "grafana-agent"
  model = juju_model.sunbeam.name


  charm {
    name     = "grafana-agent-k8s"
    base     = "ubuntu@22.04"
    channel  = var.grafana-agent-channel
    revision = var.grafana-agent-revision
  }

  units  = 1
  config = var.grafana-agent-config
}

resource "juju_integration" "grafana-agent-to-receive-remote-write" {
  count = (var.enable-observability && var.receive-remote-write-offer-url != null) ? 1 : 0
  model = juju_model.sunbeam.name

  application {
    name     = juju_application.grafana-agent[count.index].name
    endpoint = "send-remote-write"
  }

  application {
    offer_url = var.receive-remote-write-offer-url
  }
}

resource "juju_integration" "grafana-agent-to-logging" {
  count = (var.enable-observability && var.logging-offer-url != null) ? 1 : 0
  model = juju_model.sunbeam.name

  application {
    name     = juju_application.grafana-agent[count.index].name
    endpoint = "logging-consumer"
  }

  application {
    offer_url = var.logging-offer-url
  }
}

resource "juju_integration" "grafana-agent-to-cos-grafana" {
  count = (var.enable-observability && var.grafana-dashboard-offer-url != null) ? 1 : 0
  model = juju_model.sunbeam.name

  application {
    name     = juju_application.grafana-agent[count.index].name
    endpoint = "grafana-dashboards-provider"
  }

  application {
    offer_url = var.grafana-dashboard-offer-url
  }
}
