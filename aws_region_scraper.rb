require 'capybara/poltergeist'
require 'AWS'
require 'REGIONS'

module AWS
  class AmiImporter
    QUICKSTART_URL = 'https://%s.console.aws.amazon.com/ec2/ecb?call=getQuickstartList?&mbtc=%s'
    attr_reader :session, :provider_account, :user

    def initialize
      @session = begin
        Capybara.register_driver(:poltergeist) { |app| Capybara::Poltergeist::Driver.new(app, js_errors: false) }
        Capybara.default_driver = :poltergeist
        Capybara.current_session
      end
      @provider_account = ProviderAccount.first
      @user = User.first
    end

    def perform(region_id=nil)
      visit_quickstart_page
      	AWS::REGIONS.keys.each { |region_id| processor(region_id) }
      else
	processor(region_id)
      end
    end

    def processor(region_id)
      if check_json(get_json(region_id))
        save_json(get_json(region_id), region_id)
      else
        Airbrake.notify(:error_message => "AWS AMI quickstart list importer failed for region: #{region_id}")
      end
    end

    def check_json(json_resp)
      !(json_resp.include? 'No Credentials')
    end

    def get_json(region_id)
      uri = URI.parse(sprintf(QUICKSTART_URL, region_id, mbtc_value))
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      req = Net::HTTP::Post.new(uri.request_uri,
        'Content-Type' => 'application/json',
        'X-Amz-Target' => 'com.amazon.ec2consolebackend.master.EC2ConsoleBackendService.getQuickstartList',
        'Content-Encoding' => 'amz-1.0',
        'X-Requested-With' => 'XMLHttpRequest',
        'Accept' => 'application/json, text/javascript, */*',
        'Connection' => 'keep-alive',
        'Host' => 'console.aws.amazon.com',
        'Accept-Language' => 'en-US,en;q=0.8',
        'Accept-Charset' => 'ISO-8859-1,utf-8;q=0.7,*;q=0.3',
        'Cookie' => cookies
      )
      req.body = {'region' => region_id}.to_json
      binding.pry
      json_resp = http.request(req).body
    end

    def save_json(json_resp, region_id)
      file_name = "#{Rails.root}/#{AWS_CONFIG['ami_importer_path']}" % region_id
      File.open(file_name, 'w') { |f| f.write(json_resp) }
      puts "##### Saved ami quickstart image data for #{region_id} in: #{file_name}\n\n"
    end

    def cookies
      @cookies ||= session.driver.cookies.map { |k, v| c = "#{k}=#{v.value}" }.join('; ')
    end

    def mbtc_value
      @mbtc_value ||= begin
        sleep(10)
        uri = URI.parse(session.driver.network_traffic.select { |req| req.url.start_with?('https://console.aws.amazon.com/ec2/ecb?call=getQuickstartList') }.last.url)
        _mbtc = Rack::Utils.parse_query(uri.query)['mbtc']
      end
    end

    def visit_quickstart_page
      base_url = AWS::STS.get_login_url(user, provider_account)
      scrape_url = 'ec2%2Fv2%2Fhome%3Fregion%3Dus-east-1%23LaunchInstanceWizard%3A'
      session.visit base_url + scrape_url
    end
  end
end
