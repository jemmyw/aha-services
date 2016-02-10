module AhaServices::RallyWebhook
  def create_or_update_webhook
    # Find the webhook that points at this integration
    current_webhook = rally_webhook_resource.search_for_webhook(data.callback_url)

    if current_webhook
      logger.info "Updating webhook #{current_webhook.ObjectUUID} for integration: #{data.integration_id}"
      update_webhook current_webhook
    else
      logger.info "Creating webhook for integration: #{data.integration_id}"
      create_webhook
    end
  end

  def create_webhook
    rally_webhook_resource.create_webhook
  end

  def update_webhook current_webhook
    rally_webhook_resource.update_webhook current_webhook
  end

  def destroy_webhook
    current_webhook = rally_webhook_resource.search_for_webhook(data.callback_url)
    if current_webhook
      rally_webhook_resource.destroy_webhook(current_webhook)
    end
  end

  def update_record_from_webhook(payload)
    new_state = Hashie::Mash.new(Hash[ payload.message.state.map do |_, attribute|
      [attribute.name, attribute.value]
    end ])

    results = api.search_integration_fields(data.integration_id, "id", new_state.ObjectID)

    results.each do |result|
      if result.feature
        resource = result.feature
        resource_type = "feature"
        status_mappings = @service.data.feature_status_mapping
      elsif result.requirement
        resource = result.requirement
        resource_type = "requirement"
        status_mappings = @service.data.requirement_status_mapping
      else
        logger.info "Unhandled resource type for webhook: #{result.inspect}"
      end

      logger.info "Received webhook to update #{resource_type}:#{resource.id}"

      update_hash = {}
      update_hash[:description] = mapped_payload["Description"] if mapped_payload["Description"]
      update_hash[:name] = mapped_payload["Name"] if mapped_payload["Name"]
      update_hash[:workflow_status] = map_status(status_mapping, mapped_payload["State"]["name"]) if mapped_payload["State"]

      api.put(resource.resource, { resource_type => update_hash })
    end
  rescue Api::NotFound
  end

  def map_status(status_mapping, status)
    aha_status, _ = status_mapping.detect {|(_, rally_status)| rally_status == status }
    aha_status
  end
end

