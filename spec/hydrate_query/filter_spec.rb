# frozen_string_literal: true
require 'rails_helper'

describe 'Filter empty test' do
    let!(:jason)   { create(:user, email: 'jason@gmail.com') }
    before(:each) do
    end

    it 'do nothing' do
      expect(true).to be_truthy
    end

    it 'count users' do
      expect(User.count).to eq(1)
    end
end