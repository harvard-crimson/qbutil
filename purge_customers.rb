require_relative 'api'

customers = api_service(:customer)
customers.query_in_batches(nil, per_page: 20) do |batch|
  batch_request = Quickbooks::Model::BatchRequest.new
  batch.each_with_index do |customer|
    customer.active = false
    batch_request.add(customer.id, customer, 'update')
  end
  batch_response = api_service(:batch).make_request(batch_request)
  fail if batch_response.response_items.any? { |res| res.fault? }
end
