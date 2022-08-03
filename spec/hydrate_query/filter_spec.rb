# frozen_string_literal: true
require 'rails_helper'

describe 'Filter empty test' do
    let!(:jason)  { create(:user, email: 'jason@gmail.com') }
    let!(:boby)   { create(:user, email: 'boby@gmail.com') }
    let!(:sandy)  { create(:user, email: 'sandy@gmail.com') }

    it 'do nothing' do
      #DummySchema.execute('query { users { id name } }', context: {current_user: User.first })
      #res = DummySchema.execute('query { users { id first_name } }', variables: {}, context: {current_user: User.first })
      res = DummySchema.execute('query { users { id first_name } }', variables: {}, context: {current_user: User.first })
      #Graphql::HydrateQuery.new(
      #  model.all,
      #  @context,
      #  order_by: params[:order_by],
      #  filter: params[:filter],
      #  per_page: params[:per_page] && params[:per_page] > 1000 ? 1000 : params[:per_page],
      #  page: params[:page],
      #  user: user
      #).run.compact
#
      expect(res["errors"].count).to eq(0)
      expect(res["data"]["users"].count).to eq(1)
    end

    it 'count users' do
      expect(User.count).to eq(3)
    end
end