class Item < ActiveRecord::Base
  belongs_to :task
#  fill db with new records from taken url
  def Item.populate compare_type
      
    @tasks = Task.where compare_type: 1
    steam_items = nil
    html_doc  = nil
    @tasks.each do |task|
      doc = JSON.parse(open(task.url).read)
      html_doc = Nokogiri::HTML(doc['results_html'])
      steam_items = html_doc.css('.market_listing_row_link')
        
      steam_items.each do |steam_item|
        steam_item_name = steam_item.css('.market_listing_item_name').text()
        db_item = Item.where(name: steam_item_name).last
        if db_item.nil?
          steam_item_price = steam_item.at('span:contains("$")')
            .css('span').text().remove("$").remove("USD").to_f
        else
          steam_item_price = db_item.price * 2
        end
        
        if db_item.nil? || db_item.task_id != task.id
          Item.new( 
            name: steam_item_name, 
            price: steam_item_price / 2,
            active: steam_item_price > 0.09 ? 't' : 'f', 
            url: steam_item.attr('href').partition('?').first(),
            task_id: task.id,
            optimal_price: steam_item_price / 2
          ).save
        end
            
      end
        
      task.compare_type = compare_type
      task.save
    end
    @tasks.length 
  end
  
#  check if there are item with good price
  def check
    begin

      doc = JSON.parse(
        open(
          self.url.partition('?').first() + 
            "/render?start=0&count=10&currency=1&language=english&format=json"
        ).read
      )
      html_doc = Nokogiri::HTML(doc['results_html'])
      avaliable_items = html_doc.css('.market_listing_row.market_recent_listing_row')

      price = nil
      item_index = nil
      
      avaliable_items.each_with_index do |avaliable_item, index|
        price = avaliable_item.css('.market_table_value')
        .css('.market_listing_price.market_listing_price_with_fee')[0]
        .content
        .strip
        
        item_index = index
        break if price.include? "$"

      end

      ratio = AppConfig.where(name: "price_ratio").first.value.to_f
      price = price.delete('$').to_f
      
      new_item = false
      if price <= self.price * ratio && price != 0.00
        Offer.where(
          :item_id => self.id, 
          :price => price, 
          :steam_item_id => avaliable_items[item_index]
          .css('.market_listing_buy_button>a')
          .attr('href').to_s.split(', ').last()[1..-3].to_s
        ).first_or_create! do |offer|
          new_item = true
        end
        return new_item
      end
      return false
    rescue Exception => exc
      logger.error("#{exc.message} at #{Time.now} - #{self.name}")
      true
    end  
    
  end
  
end
