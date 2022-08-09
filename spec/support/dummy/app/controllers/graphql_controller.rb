class GraphqlController < ApplicationController

  # GraphQL endpoint
  def execute
    result = DummySchema.execute(
      params[:query],
      variables: ensure_hash(params[:variables]),
      context: { current_user: authenticated_user },
      operation_name: params[:operationName]
    )

    render json: result
  end

  private

  def authenticated_user
    # Here you need to authenticate the user.
  end

  # Handle form data, JSON body, or a blank value
  def ensure_hash(ambiguous_param)
    case ambiguous_param
    when String
      ambiguous_param.present? ? ensure_hash(JSON.parse(ambiguous_param)) : {}
    when Hash, ActionController::Parameters
      ambiguous_param
    when nil
      {}
    else
      raise ArgumentError, 'Unexpected parameter: ' + ambiguous_param
    end
  end

end
