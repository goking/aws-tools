aws-tools
=========

tiny tools for aws


bin/rarely.rb
---------

The solution for rarely used instances.
Create AMI automatically and terminate.

  usage: [#account-name] command parameter
    account-name: must be defined in .aws_config
    command: list, shutdown, launch
    parameter: 
      list: 'ami', 'instance'
      shutdown: instance-id
      launch: ami-id
