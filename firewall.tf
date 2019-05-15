resource "digitalocean_firewall" "wireguard" {
  name = "wireguard"

  tags = ["${var.cluster_name}-controller", "${var.cluster_name}-worker"]

  inbound_rule = [
    {
      protocol         = "udp"
      port_range       = "51820"
      source_addresses = ["0.0.0.0/0", "::/0"]
    },
  ]
}

data "aws_availability_zones" "all" {}

# Network VPC, gateway, and routes

resource "aws_vpc" "network" {
  cidr_block                       = "${var.host_cidr}"
  assign_generated_ipv6_cidr_block = true
  enable_dns_support               = true
  enable_dns_hostnames             = true

  tags = "${map("Name", "${var.cluster_name}")}"
}

resource "aws_internet_gateway" "gateway" {
  vpc_id = "${aws_vpc.network.id}"

  tags = "${map("Name", "${var.cluster_name}")}"
}

resource "aws_route_table" "default" {
  vpc_id = "${aws_vpc.network.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.gateway.id}"
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = "${aws_internet_gateway.gateway.id}"
  }

  tags = "${map("Name", "${var.cluster_name}")}"
}

# Subnets (one per availability zone)

resource "aws_subnet" "public" {
  count = "${length(data.aws_availability_zones.all.names)}"

  vpc_id            = "${aws_vpc.network.id}"
  availability_zone = "${data.aws_availability_zones.all.names[count.index]}"

  cidr_block                      = "${cidrsubnet(var.host_cidr, 4, count.index)}"
  ipv6_cidr_block                 = "${cidrsubnet(aws_vpc.network.ipv6_cidr_block, 8, count.index)}"
  map_public_ip_on_launch         = true
  assign_ipv6_address_on_creation = true

  tags = "${map("Name", "${var.cluster_name}-public-${count.index}")}"
}

resource "aws_route_table_association" "public" {
  count = "${length(data.aws_availability_zones.all.names)}"

  route_table_id = "${aws_route_table.default.id}"
  subnet_id      = "${element(aws_subnet.public.*.id, count.index)}"
}

# Security Groups (instance firewalls)

# Worker security group

resource "aws_security_group" "worker" {
  name        = "${var.cluster_name}-worker"
  description = "${var.cluster_name} worker security group"

  vpc_id = "${aws_vpc.network.id}"

  tags = "${map("Name", "${var.cluster_name}-worker")}"
}

resource "aws_security_group_rule" "worker-ssh" {
  security_group_id = "${aws_security_group.worker.id}"

  type        = "ingress"
  protocol    = "tcp"
  from_port   = 22
  to_port     = 22
  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "worker-http" {
  security_group_id = "${aws_security_group.worker.id}"

  type        = "ingress"
  protocol    = "tcp"
  from_port   = 80
  to_port     = 80
  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "worker-https" {
  security_group_id = "${aws_security_group.worker.id}"

  type        = "ingress"
  protocol    = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "worker-vxlan-self" {
  security_group_id = "${aws_security_group.worker.id}"

  type      = "ingress"
  protocol  = "udp"
  from_port = 4789
  to_port   = 4789
  self      = true
}

# Allow Prometheus to scrape node-exporter daemonset
resource "aws_security_group_rule" "worker-node-exporter" {
  security_group_id = "${aws_security_group.worker.id}"

  type      = "ingress"
  protocol  = "tcp"
  from_port = 9100
  to_port   = 9100
  self      = true
}

resource "aws_security_group_rule" "ingress-health" {
  security_group_id = "${aws_security_group.worker.id}"

  type        = "ingress"
  protocol    = "tcp"
  from_port   = 10254
  to_port     = 10254
  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "wireguard" {
  security_group_id = "${aws_security_group.worker.id}"

  type        = "ingress"
  protocol    = "udp"
  from_port   = 51820
  to_port     = 51820
  cidr_blocks = ["0.0.0.0/0"]
}

# Allow Prometheus to scrape kubelet metrics
resource "aws_security_group_rule" "worker-kubelet-self" {
  security_group_id = "${aws_security_group.worker.id}"

  type      = "ingress"
  protocol  = "tcp"
  from_port = 10250
  to_port   = 10250
  self      = true
}

resource "aws_security_group_rule" "worker-bgp-self" {
  security_group_id = "${aws_security_group.worker.id}"

  type      = "ingress"
  protocol  = "tcp"
  from_port = 179
  to_port   = 179
  self      = true
}

resource "aws_security_group_rule" "worker-ipip-self" {
  security_group_id = "${aws_security_group.worker.id}"

  type      = "ingress"
  protocol  = 4
  from_port = 0
  to_port   = 0
  self      = true
}

resource "aws_security_group_rule" "worker-ipip-legacy-self" {
  security_group_id = "${aws_security_group.worker.id}"

  type      = "ingress"
  protocol  = 94
  from_port = 0
  to_port   = 0
  self      = true
}

resource "aws_security_group_rule" "worker-egress" {
  security_group_id = "${aws_security_group.worker.id}"

  type             = "egress"
  protocol         = "-1"
  from_port        = 0
  to_port          = 0
  cidr_blocks      = ["0.0.0.0/0"]
  ipv6_cidr_blocks = ["::/0"]
}
