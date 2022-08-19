# frozen_string_literal: true
require "rails_helper"

NOW = DateTime.now

describe "Generating some data, performing a graphql query" do
  def run_query(query, order_by="")
    DummySchema.execute(
      query,
      variables: { order_by: order_by },
      context: { current_user: User.first },
    )
  end

  def house_query(order_by)
    res = run_query("query($order_by: String) { houses(order_by: $order_by) { id street energy_grade principal } }", order_by)
    puts res["errors"] if res["errors"].present?
    expect(res["errors"].nil?).to be_truthy
    res["data"]["houses"]
  end

  let!(:berlin) { create(:city, name: "Berlin") }
  let!(:paris) { create(:city, name: "Paris") }

  let!(:jason) { create(:user, email: "jason@gmail.com") }
  let!(:boby) { create(:user, email: "boby@gmail.com") }
  let!(:sandy) { create(:user, email: "sandy@gmail.com") }
  let!(:mike) { create(:user, email: "mike@gmail.com") }
  let!(:gavin) { create(:user, email: "gavin@gmail.com") }
  let!(:jc) { create(:user, email: "jean-claude@gmail.com") }

  let!(:house1) { create(:house, user: jason, city: berlin, street: "street1", number: 1, price: 25_000, energy_grade: "d", principal: true, build_at: NOW - 2.day) }
  let!(:house2) { create(:house, user: boby, city: berlin, street: "street2", number: 10, price: 30_000, energy_grade: "a", principal: true, build_at: NOW - 1.day) }
  let!(:house3) { create(:house, user: sandy, city: berlin, street: "street3", number: 100, price: 100_000, energy_grade: "b", principal: true, build_at: NOW + 1.day) }
  let!(:house4) { create(:house, user: mike, city: berlin, street: "street4", number: 150, price: 200_000, energy_grade: "b", principal: true, build_at: NOW + 2.day) }
  let!(:house5) { create(:house, user: gavin, city: berlin, street: "street5", number: 350, price: 1_250_000, energy_grade: "c", principal: false, build_at: NOW + 4.day) }
  let!(:house42) { create(:house, user: jc, city: paris, street: "street42", number: 200, price: 400_000.05, energy_grade: "a", principal: false, build_at: NOW + 3.day) }

  it "with a order_by on a string" do
    expect(house_query("street ASC").pluck("street")).to eq([
      "street1",
      "street2",
      "street3",
      "street4",
      "street42",
      "street5",
    ])

    expect(house_query("street DESC").pluck("street")).to eq([
      "street5",
      "street42",
      "street4",
      "street3",
      "street2",
      "street1",
    ])
  end

  it "with a order_by on a with no direction" do
    expect(house_query("street").pluck("street")).to eq([
      "street1",
      "street2",
      "street3",
      "street4",
      "street42",
      "street5",
    ])
  end

  it "with a order_by on a int" do
    expect(house_query("number ASC").pluck("street")).to eq([
      "street1",
      "street2",
      "street3",
      "street4",
      "street42",
      "street5",
    ])

    expect(house_query("number DESC").pluck("street")).to eq([
      "street5",
      "street42",
      "street4",
      "street3",
      "street2",
      "street1",
    ])
  end

  it "with a order_by on a float" do
    expect(house_query("price ASC").pluck("street")).to eq([
      "street1",
      "street2",
      "street3",
      "street4",
      "street42",
      "street5",
    ])

    expect(house_query("price DESC").pluck("street")).to eq([
      "street5",
      "street42",
      "street4",
      "street3",
      "street2",
      "street1",
    ])
  end

  it "with a order_by on a datetime" do
    expect(house_query("build_at ASC").pluck("street")).to eq([
      "street1",
      "street2",
      "street3",
      "street4",
      "street42",
      "street5",
    ])

    expect(house_query("build_at DESC").pluck("street")).to eq([
      "street5",
      "street42",
      "street4",
      "street3",
      "street2",
      "street1",
    ])
  end

  it "with a order_by on a bool" do
    expect(house_query("principal ASC").pluck("principal")).to eq([
      false,
      false,
      true,
      true,
      true,
      true,
    ])

    expect(house_query("principal DESC").pluck("principal")).to eq([
      true,
      true,
      true,
      true,
      false,
      false,
    ])
  end

  it "with a order_by on a belongs_to association string field" do
    expect(house_query("user.email ASC").pluck("street")).to eq([
      "street2",
      "street5",
      "street1",
      "street42",
      "street4",
      "street3",
    ])

    expect(house_query("user.email DESC").pluck("street")).to eq([
      "street3",
      "street4",
      "street42",
      "street1",
      "street5",
      "street2",
    ])
  end

  it "with a blank order_by" do
    expect(house_query("").count).to eq(6)
  end
end
