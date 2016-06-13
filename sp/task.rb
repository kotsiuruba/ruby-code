class Task < ActiveRecord::Base
  
  has_many :items, dependent: :destroy
 
#  parse single item info and send notificate if item is needed
  def Task.single_item
    @tasks = self.where compare_type: 1
      
    items = Array.new
    sleep_value = (60 / (@tasks.length + 1).to_f).to_i

    @tasks.each do |task|
      begin
        doc = JSON.parse(
          open(
            task.url + "/render?start=0&count=10&currency=1&language=english&format=json"
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

        price = price.delete('$').to_f

        if price <= task.price && price != 0.00

          items << {
            :url => task.url,
            :name => task.item_name,
            :price => price,
            :wanted_price => task_item.price,
            :image => html_doc
            .css('.market_listing_row.market_recent_listing_row')[item_index]
            .css('.market_listing_item_img_container')[0]
            .css('img')[0]
            .attr('src')
          }
          
        end
        
      rescue Exception => exc
        logger.error("#{exc.message} at #{Time.now} - #{task.item_name}")
      end  
      
      sleep sleep_value
      
    end

    if items.length > 0
      TaskMailer.notification(items).deliver! 
    end
    items
  end
  
  
  def Task.update_current_price compare_type

    @tasks = Task.where(compare_type: compare_type).order 'id'
    sleep_value = (60 / (@tasks.length + 1).to_f).to_i
    @tasks.each do |task|
      begin
        doc = JSON.parse(open(task.url).read)
        html_doc = Nokogiri::HTML(doc['results_html'])

        task_item = task.items.first
        task.items.each do |task_item|

          steam_item = html_doc
          .css('.market_listing_row.market_recent_listing_row.market_listing_searchresult')
          .at("[text()=\"#{task_item.name.to_s.strip}\"]")
          if !steam_item.nil?
            price = steam_item.parent()
            .parent()
            .at('span:contains("$")')
            .css('span')
            .text()
            .remove("$")
            .remove("USD").to_f

            task_item.current_price = price
            task_item.image = steam_item.parent().parent()
              .css('.market_listing_item_img').attr('src').value()
            
            task_item.save!
          end

        end
      rescue Exception => exc
        logger.error("#{exc.message} at #{Time.now} - #{task.item_name}")
      end
      sleep sleep_value
    end
  end
end
