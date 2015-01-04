require 'thread'

require_relative 'api'

POOL_SIZE = 15

queue = Queue.new

accounts = api_service(:account)

Thread.new do
  accounts.query_in_batches(nil, per_page: 20) do |batch|
    batch_request = Quickbooks::Model::BatchRequest.new

    batch.each do |account|
      queue << account
    end
  end
  POOL_SIZE.times { queue << false }
end

workers = (0...POOL_SIZE).map do
  Thread.new do
    while account = queue.pop
      puts "Deleting account #{account.name.inspect}"
      accounts.delete(account)
    end
  end
end

workers.each { |worker| worker.join }
