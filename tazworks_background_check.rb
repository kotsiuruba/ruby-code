class TazworksBackgroundCheck
  include Rails.application.routes.url_helpers

  attr_accessor :response, :errors
  attr_reader :background_check

  def initialize background_check
    @background_check = background_check
    @request = nil
    @errors = []
  end

  # send request for backgrond check
  def initial_request data
    generate_request data, [
      {type: 'x:embed_credentials', text: 'YES'},
      {type: 'x:interface', text: 'Applicant'},
      {type: 'x:quickapp_redirect_url', text: root_url},
      {type: 'x:postback_url', text: background_checks_update_status_url},
      {type: 'x:integration_type', text: 'MinistrySafe'}
    ]
    send_request
  end

  # generate request for check background check decigion         
  def report_decision data
    generate_request data, [{type: 'x:decision_model', text: 'REPORT'}]
    send_request
  end

  #parse node and return value
  def parse node
    xml_doc = Nokogiri::XML(@response)
    CGI::unescapeHTML xml_doc.css(node).first.text
  end

  #generate request. return xml
  def generate_request data, additional_items = []
    builder = Nokogiri::XML::Builder.new do |xml|
      xml.BackgroundCheck(
        'userId' => @background_check.user.organization.data_source_code.to_s,
        'password' => ENV['TAZWORKS_PASSWORD']
      ){
        
        xml.BackgroundSearchPackage(
          'action' => 'submit',
          'type' => "#{@background_check.user.user_type.to_s.capitalize} Package #{@background_check.level.humanize}"
        ){
          
          xml.ReferenceId @background_check.id
          xml.PersonalData{
            xml.PersonName{
              xml.GivenName data["given_name"]
              xml.FamilyName data["family_name"]
              xml.MiddleName
            }
            xml.EmailAddress data["email"]
          }
          xml.Screenings('useConfigurationDefaults' => 'yes'){
            additional_items.each do |item|
              xml.AdditionalItems('type' => item[:type]){
                xml.Text item[:text]
              }
            end
          }
        }
      }
    end
    @request = builder.to_xml
  end
  
  # send generated request to needed url of api
  def send_request
    if background_check.user.organization.site == 1
      site_url = "ministrysafe"
    else
      site_url = "abusepreventionsystems"
    end

    RestClient.proxy = ENV["PROXIMO_URL"] if ENV["PROXIMO_URL"]
    @response = RestClient.post(
      "https://reports.#{site_url}.com/send/interchange",
      :request => @request
    ).to_s
  end

  #process requests and responces from taz api
  def self.process_response xml
    begin
      data = Nokogiri::XML(xml)
      user_id = data.xpath("//BackgroundReports").first.attribute('userId').value
      password = data.xpath("//BackgroundReports").first.attribute('password').value
      background_check = BackgroundCheck.find data.xpath("//ReferenceId").first.text.to_i
      #check auth
      if(!background_check.nil? && 
            (user_id == background_check.user.organization.data_source_code.to_s) && 
            password == ENV['TAZWORKS_PASSWORD'])
        check = self.new background_check
      else
        check = self.new nil
        check.errors << "Bad credentils"
      end
    rescue => e
      check = self.new nil
      check.errors << "Bad request"
    end
    check.response = xml
    check
  end

  def self.sub_login(site)
    site == 2 ? "APXML_" : "MSXML_"
  end
end
