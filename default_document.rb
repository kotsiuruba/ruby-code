class DefaultDocument < ActiveRecord::Base
	belongs_to :creator, class_name: "User", foreign_key: :creator_id
	
	has_many :default_document_elements, dependent: :destroy

	validates :name, presence: true
	accepts_nested_attributes_for :default_document_elements, allow_destroy: true, reject_if: :type_does_not_match

	scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :filter, ->(value) {
    where("LOWER(#{self.table_name}.name) like LOWER('%#{value}%')")
  }

  enum category: {application: '0', procedure: '1', other: '2', reference: '3'}
  include EnumSortable
  
  after_create :replicate

	def self.load_from_defaults documents = nil
    require "#{Rails.root}/lib/defaults"
  	documents ||= Defaults::load_documents
  	documents.each do |row|
	    document = DefaultDocument.new({
	      name: row[:name],
	      category: row[:category],
	      active: true,
	      e_sign_verification: row[:e_sign_verification].nil? ? false : row[:e_sign_verification],
	      is_readonly: row[:readonly].nil? ? true : row[:readonly],
	      site: row[:site]
	    })
	    if document.save
	      row[:elements].each do |element|
	        DocumentElement.create(element.merge({document: document}))
	      end
	    end
  	end
	end

#  replicate all default documents for organization(s)
  def self.replicate_all(organizations=nil)
    organizations ||= Organization.active
    default_documents = DefaultDocument.all
    default_documents.each do |document|
      document.replicate organizations
    end
    
  end
  
# replicate document for organization  
  def replicate(organizations=nil)
    organizations ||= Organization.active
    organizations.each do |organization|
      if organization.site == site
        document = Document.new(
          attributes.slice(*(Document.attribute_names - ["id"]))
        )
        document.organization_id = organization.id
        document.is_default = true

        default_document_elements.each do |element|
          document.document_elements << DocumentElement.new(
            element.attributes.slice(*(DocumentElement.attribute_names - ["id"]))
          )
        end
        document.save!
      end
    end
  end
  
end
