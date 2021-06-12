provider "aws" {
  region = "ap-south-1"
  profile = "vibhav1"
}

resource "aws_vpc" "myvpc" {
  cidr_block       = "192.168.0.0/16"
  instance_tenancy = "default"
  enable_dns_hostnames = "true"
  tags = {
    Name = "myvpct4"
  }
}

# Creating Public Subnet for Wordpress
resource "aws_subnet" "subnet1-wp" {
  depends_on = [ aws_vpc.myvpc ]
  vpc_id     = "${aws_vpc.myvpc.id}"
  cidr_block = "192.168.1.0/24"
  availability_zone = "ap-south-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "wp_subnet"
  }
}

# Creating Internet Gateway for wordpress
resource "aws_internet_gateway" "mygw" {
  depends_on = [ aws_vpc.myvpc ]
  vpc_id = "${aws_vpc.myvpc.id}"
  tags = {
    Name = "myigw"
  }
}

# Creating Routing Table for Internet Gateway
resource "aws_route_table" "route-table" {
  depends_on = [ aws_internet_gateway.mygw ]
  vpc_id =   aws_vpc.myvpc.id 
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.mygw.id}"
  }
  tags = {
    Name = "wproute-table"
  }
}

# Associating Routing Table with Public Subnet
resource "aws_route_table_association" "route-table-association" {
  depends_on = [ 
    aws_route_table.route-table,
   ]
  subnet_id      = aws_subnet.subnet1-wp.id
  route_table_id = aws_route_table.route-table.id
}

# Security group for wordpress inside public subnet
resource "aws_security_group" "sg1" {
  depends_on = [ aws_vpc.myvpc ]
  name        = "sg1-public"
  description = "Allow inbound traffic ssh and http"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    description = "allow ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "allow http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_ssh_httpd"
  }
}

# Creating Private Subnet for Mysql
resource "aws_subnet" "subnet2-mysql" {
  depends_on = [ aws_vpc.myvpc ]
  vpc_id     = aws_vpc.myvpc.id
  cidr_block = "192.168.2.0/24"
  availability_zone = "ap-south-1b"
  tags = {
    Name = "sql_subnet"
  }
}

# Security group for wordpress inside public subnet
resource "aws_security_group" "sg2-mysql" {
  depends_on = [ aws_vpc.myvpc ]
  name        = "sg1-private"
  description = "Allow inbound traffic mysql from public subnet security group"
  vpc_id      =  "${aws_vpc.myvpc.id}"

  ingress {
    description = "allow ssh"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [ aws_security_group.sg1.id ]
  }
  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_mysql"
  }
}

# Assigning elastic IP for vpc
resource "aws_eip" "elastic_ip" {
  vpc      = true
}
# Nat Gateway
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = "${aws_eip.elastic_ip.id}"
  subnet_id     = "${aws_subnet.subnet1-wp.id}"
  depends_on    = [ aws_internet_gateway.mygw ]
}

resource "aws_route_table" "nat-rtable" {
  vpc_id = "${aws_vpc.myvpc.id}"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_nat_gateway.nat_gw.id}"
  }
  tags = {
    Name = "nat-routetable"
  }
}

resource "aws_route_table_association" "nat-b" {
  subnet_id      = aws_subnet.subnet2-mysql.id
  route_table_id = aws_route_table.nat-rtable.id
}

# security group for bastion
resource "aws_security_group" "bastion-sg" {
  name        = "bastion-sg"
  description = "SSH to bastion-host"
  vpc_id      = "${aws_vpc.myvpc.id}"
  
  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "sgroup"
  }
}

# Wordpress instance
resource "aws_instance" "wp" {
  depends_on = [ aws_security_group.sg1,aws_subnet.subnet1-wp,aws_instance.mysql ]
  ami = "ami-01a2ff9c279ef2f3e"
  instance_type = "t2.micro"
  
  vpc_security_group_ids = [ aws_security_group.sg1.id ]
  subnet_id = aws_subnet.subnet1-wp.id
  associate_public_ip_address = "true"
  key_name = "mykey111222"

  tags = {
    Name = "wordpress"
  }
}

# Mysql instance
resource "aws_instance" "mysql" {
  depends_on = [ aws_security_group.sg2-mysql,aws_subnet.subnet2-mysql ]
  ami = "ami-01ac60177565974ce"
  instance_type = "t2.micro"
  
  vpc_security_group_ids = [ aws_security_group.sg2-mysql.id ]
  subnet_id = aws_subnet.subnet2-mysql.id
  
  tags = {
    Name = "mysql"
  }
}

#instance for Bastion-host
resource "aws_instance" "bastion-host" {
  ami           = "ami-00b494a3f139ba61f"
  instance_type = "t2.micro"
  key_name      = "mykey111222"
  availability_zone = "ap-south-1a"
  subnet_id     = "${aws_subnet.subnet1-wp.id}"
  vpc_security_group_ids = [ "${aws_security_group.bastion-sg.id}" ]
  tags = {
    Name = "bastion-host"
  }
}

