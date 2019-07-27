#!/bin/bash

# Setup variables here.
encryption_passphrase=""
root_password=""
user_password=""
hostname=""
user_name=""
continent_city=""
swap_size="8"


echo "Updating system clock"
timedatectl set-ntp true

# Query for disk to install to
