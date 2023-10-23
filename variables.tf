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

variable "openstack-channel" {
  description = "Operator channel for OpenStack deployment"
  default     = "2023.2/edge"
}

variable "mysql-channel" {
  description = "Operator channel for MySQL deployment"
  default     = "8.0/candidate"
}

variable "mysql-router-channel" {
  description = "Operator channel for MySQL router deployment"
  default     = "8.0/candidate"
  type        = string
}

variable "rabbitmq-channel" {
  description = "Operator channel for RabbitMQ deployment"
  default     = "3.12/edge"
}

variable "ovn-channel" {
  description = "Operator channel for OVN deployment"
  default     = "23.09/edge"
}

variable "model" {
  description = "Name of Juju model to use for deployment"
  default     = "openstack"
}

variable "cloud" {
  description = "Name of K8S cloud to use for deployment"
  default     = "microk8s"
}

# https://github.com/juju/terraform-provider-juju/issues/147
variable "credential" {
  description = "Name of credential to use for deployment"
  default     = ""
}

variable "config" {
  description = "Set configuration on model"
  default     = {}
}

variable "enable-ceph" {
  description = "Enable Ceph integration"
  default     = false
}

variable "ceph-offer-url" {
  description = "Offer URL from microceph app"
  default     = "admin/controller.microceph"
}

variable "ceph-osd-replication-count" {
  description = "Ceph OSD replication count to set on glance/cinder"
  default     = 1
}

variable "ha-scale" {
  description = "Scale of traditional HA deployments"
  # Need better name, because 1 is not HA, needs to encompass services like MySQL, RabbitMQ and OVN
  default = 1
}

variable "os-api-scale" {
  description = "Scale of OpenStack API service deployments"
  default     = 1
}

variable "ingress-scale" {
  description = "Scale of ingress deployment"
  default     = 1
}

variable "many-mysql" {
  description = "Enabling this will switch architecture from one global mysql to one per service"
  default     = false
}

variable "enable-heat" {
  description = "Enable OpenStack Heat service"
  default     = false
}

# Temporary channel for heat until 2023.2/stable is released.
variable "heat-channel" {
  description = "Operator channel for OpenStack Heat deployment"
  default     = "2023.2/edge"
}

variable "enable-telemetry" {
  description = "Enable OpenStack Telemetry services"
  default     = false
}

# Temporary channel for telemetry services until 2023.2/stable is released.
variable "telemetry-channel" {
  description = "Operator channel for OpenStack Telemetry deployment"
  default     = "2023.2/edge"
}

variable "enable-octavia" {
  description = "Enable OpenStack Octavia service"
  default     = false
}

# Temporary channel for octavia until 2023.2/stable is released.
variable "octavia-channel" {
  description = "Operator channel for OpenStack Octavia deployment"
  default     = "2023.2/edge"
}
variable "enable-designate" {
  description = "Enable OpenStack Designate service"
  default     = false
}

variable "designate-channel" {
  description = "Operator channel for OpenStack Designate deployment"
  default     = "2023.2/edge"
}

variable "bind-channel" {
  description = "Operator channel for Bind deployment"
  default     = "9/edge"
}

variable "nameservers" {
  description = <<-EOT
    Space delimited list of nameservers. These are the nameservers that have been provided
    to the domain registrar in order to delegate the domain to Designate.
    e.g. "ns1.example.com. ns2.example.com."
  EOT
  default     = ""
}

variable "enable-vault" {
  description = "Enable Vault service"
  default     = false
}

variable "vault-channel" {
  description = "Operator channel for Vault deployment"
  default     = "latest/edge"
}

variable "enable-barbican" {
  description = "Enable OpenStack Barbican service"
  default     = false
}

variable "barbican-channel" {
  description = "Operator channel for OpenStack Barbican deployment"
  default     = "2023.2/edge"
}

variable "enable-magnum" {
  description = "Enable OpenStack Magnum service"
  default     = false
}

variable "magnum-channel" {
  description = "Operator channel for OpenStack Magnum deployment"
  default     = "2023.2/edge"
}

variable "ldap-channel" {
  description = "Operator channel for Keystone LDAP deployment"
  default     = "2023.2/edge"
}

variable "ldap-apps" {
  description = "LDAP Apps and their config flags"
  type        = map(map(string))
  default     = {}
}
