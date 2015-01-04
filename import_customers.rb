require 'smarter_csv'
require 'thread'

require_relative 'api'

POOL_SIZE = 15

queue = Queue.new

borked = []

customers = api_service(:customer)

SmarterCSV.process(ARGV[0]).each do |customer|
  customer[:zip] = "0" + customer[:zip].to_s if customer[:zip].to_s.length < 5
  customer[:company_name] = customer.delete(:company)
  customer[:primary_phone] = Quickbooks::Model::TelephoneNumber.new(
    customer.delete(:phone))
  customer[:billing_address] = Quickbooks::Model::PhysicalAddress.new(
    line1: customer.delete(:street),
    city: customer.delete(:city),
    country_sub_division_code: customer.delete(:state),
    postal_code: customer.delete(:zip))
  queue << [Quickbooks::Model::Customer.new(customer), 5]
end

Quickbooks.log = true

workers = (0...POOL_SIZE).map do
  Thread.new do
    while popped = queue.pop
      customer, retries = popped
      puts "Importing customer #{customer.display_name.inspect}"
      begin
        customers.create(customer)
      rescue Quickbooks::IntuitRequestException => e
        p e
        if retries > 0
          queue << [customer, retries - 1]
        else
          borked << customer
        end
      end
    end
  end
end

workers.each { |worker| worker.join }

p borked
