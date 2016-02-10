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
      value = attribute.value
      # User story webhooks get passed back as a status object, with a nested value
      if value.is_a? Hashie::Mash
        value = value.name
      end
      [attribute.name, value]
    end ])

    results = api.search_integration_fields(data.integration_id, "id", new_state.ObjectID)["records"] rescue []

    results.each do |result|
      if result.feature
        resource = result.feature
        resource_type = "feature"
        status_mappings = data.feature_statuses
      elsif result.requirement
        resource = result.requirement
        resource_type = "requirement"
        status_mappings = data.requirement_statuses
      else
        logger.info "Unhandled resource type for webhook: #{result.inspect}"
      end

      logger.info "Received webhook to update #{resource_type}:#{resource.id}"

      update_hash = {}
      update_hash[:description] = new_state["Description"] if new_state["Description"]
      update_hash[:name] = new_state["Name"] if new_state["Name"]
      if new_state["State"] && (new_status = status_mappings[new_state["State"]["name"]])
        update_hash[:workflow_status] = new_status
      end

      api.put(resource.resource, { resource_type => update_hash })
    end
  rescue AhaApi::NotFound
    logger.warn "No record found for reference: #{new_state.ObjectID}"
  end
end

