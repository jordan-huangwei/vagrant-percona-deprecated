# -*- mode: ruby -*-
# vi: set ft=ruby :

require File.dirname(__FILE__) + '/lib/vagrant-common.rb'

# Number of servers
ps_servers = 1

# AWS configuration
aws_region = "us-east-1"
aws_ips='private' # Use 'public' for cross-region AWS.  'private' otherwise (or commented out)
security_groups = []


serverlist="ps1,";
(2..ps_servers).each { |i|
  serverlist=serverlist + ',ps' + i.to_s;
}


Vagrant.configure("2") do |config|
	config.vm.box = "grypyrg/centos-x86_64"
	config.vm.box_version = "~> 7"
	config.ssh.username = "vagrant"

  # Create the PXC nodes
  (1..ps_servers).each do |i|
    name = "ps" + i.to_s
    config.vm.define name do |node_config|
      node_config.vm.hostname = name
      node_config.vm.network :private_network, type: "dhcp"
      node_config.vm.provision :hostmanager
      
      # Provisioners
      provision_puppet( node_config, "percona_server.pp" ) { |puppet| 
        puppet.facter = {
          'cluster_servers' => serverlist,
          # PXC setup
          "percona_server_version"  => '56',
          'innodb_buffer_pool_size' => '128M',
          'innodb_log_file_size' => '64M',
          'innodb_flush_log_at_trx_commit' => '0',
         
          # Sysbench setup
          'sysbench_load' => (i == 1 ? true : false ),
          'tables' => 1,
          'rows' => 1000000,
          'threads' => 1,
          # 'tx_rate' => 10,
          
          # TokuDB setup
          'tokudb_enable' => true,
          'tokudb_directio' => 'ON',
          'tokudb_loader_memory_size' => '64M',
          'tokudb_fsync_log_period' => '0',
          'tokudb_cache_size' => '128M',
            
          # Vividcortexv setup
          'vividcortex_api_key' => ENV['VIVIDCORTEX_API_KEY'],
          
        }
      }

      # Providers
      provider_virtualbox( nil, node_config, 1024 ) { |vb, override|
        provision_puppet( override, "percona_server.pp" ) {|puppet|
          puppet.facter = {
            'default_interface' => 'eth1',
            'datadir_dev' => 'dm-2',
          }
        }
      }

      provider_vmware( name, node_config, 1024 ) { |vb, override|
        provision_puppet( override, "percona_server.pp" ) {|puppet|
          puppet.facter = {
            'default_interface' => 'eth1',
            'datadir_dev' => 'dm-2',
          }
        }
      }
  
      provider_aws( "Percona Server #{name}", node_config, 'm3.medium', aws_region, security_groups, aws_ips) { |aws, override|

        aws.block_device_mapping = [
            {
                'DeviceName' => "/dev/sdl",
                'VirtualName' => "mysql_data",
                'Ebs.VolumeSize' => 20,
                'Ebs.DeleteOnTermination' => true,
            }
        ]

        provision_puppet( override, "percona_server.pp" ) { |puppet| 
          puppet.facter = {'datadir_dev' => 'xvdl'}        
        }
      }

      provider_openstack( 'Packer Server #{name}', node_config, 'm1.small', nil, ['cc7e31d8-a4aa-4544-8a74-86dfd06655d7'] ) { |os, override|
        os.disks = [
          { "name" => "#{name}-data", "size" => 10, "description" => "MySQL Data"}
        ]
        provision_puppet( override, "percona_server.pp" ) { |puppet| 
          puppet.facter = {'datadir_dev' => 'vdb'}        
        }
      }
      
      provider_openstack( "Percona Server #{name}", node_config, 'm1.small', nil, 'cc7e31d8-a4aa-4544-8a74-86dfd06655d7' ) { |os, override|
        os.disks = [
          { "name" => "#{name}-data", "size" => 100, "description" => "MySQL Data"}
        ]
        provision_puppet( override, "percona_server.pp" ) { |puppet| 
          puppet.facter = {'datadir_dev' => 'vdb'}        
        }
      }

    end
  end
  
end
