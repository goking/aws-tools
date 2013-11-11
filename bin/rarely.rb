require 'rubygems'
require 'aws-sdk'
require 'time'

# たまにしか使わないインスタンスの起動と停止を管理する

if ARGV.empty?
  puts <<-EOL
    usage: [#account-name] command parameter
      account-name: must be defined in .aws_config
      command: list, shutdown, launch
      parameter: 
        list: 'ami', 'instance'
        shutdown: instance-id
        launch: ami-id
  EOL
end

config = YAML.load_file(".aws_config")
account_name = (/^#/ =~ ARGV.first) ? ARGV.shift : "default"
account = config[account_name]
AWS.config(
  access_key_id: account["access_key_id"], 
  secret_access_key: account["secret_access_key"], 
  region: account["region"])

class Rarely

  def initialize(account, argv)
    @account = account
    @cmd = argv.shift
    @tgt = argv.shift
    @ec2 = AWS.ec2
  end

  def run
    case @cmd
    when "list"
      case @tgt
      when "ami"
        list_ami
      when "instance"
        list_running
      else
        raise "can't list: #{@tgt}"
      end
    when "shutdown"
      shutdown
    when "launch"
      launch
    else
      raise "no such cmd: #{@cmd}"
    end
  end

  # list ami
  # タグRarely付きのAMIのリストを表示
  def list_ami
    @ec2.images.with_owner('self').tagged('Rarely').each do |i|
      puts "#{i.id}\t#{i.name}"
    end
  end

  # list instance
  # タグRarely付きのインスタンスのリストを表示
  def list_instance
    @ec2.instances.tagged('Rarely').each do |i|
      puts "#{i.id}\t#{i.image_id}\t#{i.tags.Name}"
    end
  end

  # shutdown [instance-id]
  # 指定したインスタンスのスナップショットAMIを作って停止する
  # 作成されるAMIの名前は、インスタンス名にタイムスタンプを付加したものとなる
  # 元のインスタンス名はAMIのRarelyタグに設定される 
  def shutdown
    instance = @ec2.instances.tagged('Rarely')[@tgt]
    raise "instance not found: #{@tgt}" unless instance.exists?
    if instance.status == :running
      puts "stopping instance: #{instance.id}"
      instance.stop
      wait_while(instance, :status, :stopping)
    end
    puts "creating snapshot ami"
    timestamp = Time.now.strftime("%FT%H.%M.%S%Z")
    name = "#{instance.tags.Name} (#{timestamp})"
    desc = "created by Rarely at #{timestamp}"
    image = instance.create_image(name, description: desc, no_reboot: true)
    image.tag('Rarely', value: instance.tags.Name)
    wait_while(image, :state, :pending)
    if image.state == :failed
      raise "unable to create snapshot image: #{image.state_reason.message}"
    end
    puts "new snapshot ami: #{image.id}"
    puts "terminating instance: #{instance.id}"
    old_image_id = instance.image_id
    instance.terminate
    wait_while(instance, :status, :sutting_down)
    old_image = @ec2.images.with_owner('self')[old_image_id]
    if old_image.exists? && old_image.tags.has_key?('Rarely')
      puts "deregister old ami: #{old_image.id}"
      old_image.deregister
    end
    puts "completed!"
  end

  # launch [ami-id]
  # 指定したAMIを使ってインスタンスを起動する
  # AMIのRarelyタグの文字列がインスタンス名となる
  def launch
    image = @ec2.images.with_owner('self').tagged('Rarely')[@tgt]
    raise "ami not found: #{@tgt}" unless image.exists?
    raise "unable to use #{@tgt}: #{image.state}" unless image.state == :available
    puts "using ami: #{image.name}"
    options = {}
    @account["launch_opts"].keys.each do |key|
      options[key.to_sym] = @account["launch_opts"][key]
    end
    instance = image.run_instance(options)
    name = image.tags.Rarely || image.name
    instance.tag('Name', value: name)
    instance.tag('Rarely')
    puts "launching: #{instance.id}"
    wait_while(instance, :status, :pending)
    puts "completed!"
    puts "public-dns: #{instance.public_dns_name}"
  end

  private

  def wait_while(target, method, value)
    times = 0
    while target.send(method) == value
      times += 1
      print "\rwaiting progress: #{'*'*times}"
      sleep 2
    end
    puts if times > 0
  end
end

rarely = Rarely.new(account, ARGV)
rarely.run