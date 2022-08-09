# frozen_string_literal: true
require "rails_helper"

NOW = DateTime.now

describe "Generating some data, performing a graphql query" do
  def run_query(query, filter="")
    DummySchema.execute(
      query,
      variables: { filter: filter },
      context: { current_user: User.first },
    )
  end

  def house_query(filter)
    res = run_query("query($filter: String) { houses(filter: $filter) { id } }", filter)
    puts res["errors"] if res["errors"].present?
    expect(res["errors"].nil?).to be_truthy
    res["data"]["houses"]
  end

  let!(:berlin) { create(:city, name: "Berlin") }
  let!(:paris) { create(:city, name: "Paris") }

  let!(:jason) { create(:user, email: "jason@gmail.com") }
  let!(:boby) { create(:user, email: "boby@gmail.com") }
  let!(:sandy) { create(:user, email: "sandy@gmail.com") }

  let!(:house1) { create(:house, user: jason, city: berlin, street: "street1", number: 1, price: 25_000, energy_grade: "d", principal: true, build_at: NOW - 1.day) }
  let!(:house2) { create(:house, user: jason, city: berlin, street: "street1", number: 10, price: 30_000, energy_grade: "a", principal: true, build_at: NOW - 1.day) }
  let!(:house3) { create(:house, user: jason, city: berlin, street: "street1", number: 50, price: 50_000, energy_grade: "a", principal: true, build_at: NOW - 1.day) }
  let!(:house4) { create(:house, user: jason, city: berlin, street: "street1", number: 75, price: 60_000, energy_grade: "b", principal: true, build_at: NOW - 1.day) }
  let!(:house5) { create(:house, user: jason, city: berlin, street: "street1", number: 100, price: 100_000, energy_grade: "b", principal: true, build_at: NOW + 1.day) }
  let!(:house6) { create(:house, user: boby, city: berlin, street: "street1", number: 150, price: 200_000, energy_grade: "b", principal: true, build_at: NOW + 1.day) }
  let!(:house7) { create(:house, user: boby, city: berlin, street: "street1", number: 200, price: 400_000.05, energy_grade: "c", principal: false, build_at: NOW + 1.day) }
  let!(:house8) { create(:house, user: boby, city: berlin, street: "street1", number: 250, price: 800_000.23, energy_grade: "c", principal: false, build_at: NOW + 1.day) }
  let!(:house9) { create(:house, user: sandy, city: berlin, street: "street1", number: 300, price: 1_000_000, energy_grade: "c", principal: false, build_at: NOW + 1.day) }
  let!(:house10) { create(:house, user: sandy, city: paris, street: "street42", number: 350, price: 1_250_000, energy_grade: "a", principal: false, build_at: NOW + 1.day) }

  it "with no filter" do
    res = run_query("query { users { id first_name } }")

    expect(res["errors"].nil?).to be_truthy
    expect(res["data"]["users"].count).to eq(3)
  end

  it "with a filter on a string" do
    expect(house_query("street == 'street42'").count).to eq(1)
    expect(house_query("street != 'street42'").count).to eq(9)
    expect(house_query("street == 'unknown street'").count).to eq(0)
    # test case sensitivity
    expect(house_query("street == 'strEEt42'").count).to eq(1)
    expect(house_query("street === 'strEEt42'").count).to eq(0)
    expect(house_query("street != 'strEEt42'").count).to eq(9)
    expect(house_query("street !== 'strEEt42'").count).to eq(10)
  end

  it "with a filter on a double quoted string" do
    expect(house_query("street == \"street42\"").count).to eq(1)
  end

  it "with a filter on a uuid" do
    expect(house_query("id == '#{house1.id}'").count).to eq(1)
  end

  it "with a filter on a int" do
    expect(house_query("number > 100").count).to eq(5)
    expect(house_query("number >= 100").count).to eq(6)
    expect(house_query("number < 50").count).to eq(2)
    expect(house_query("number <= 50").count).to eq(3)
    expect(house_query("number == 50").count).to eq(1)
    expect(house_query("number == 50").count).to eq(1)
    expect(house_query("number != 50").count).to eq(9)
  end

  it "with a filter on a float" do
    expect(house_query("price > 100000").count).to eq(5)
    expect(house_query("price >= 100000").count).to eq(6)
    expect(house_query("price < 50000").count).to eq(2)
    expect(house_query("price <= 50000").count).to eq(3)
    expect(house_query("price == 50000").count).to eq(1)
    expect(house_query("price != 50000").count).to eq(9)
  end

  it "with a filter on a datetime" do
    expect(house_query("build_at > '#{NOW}'").count).to eq(6)
    expect(house_query("build_at < '#{NOW}'").count).to eq(4)
    expect(house_query("build_at >= '#{NOW}'").count).to eq(6)
    expect(house_query("build_at <= '#{NOW}'").count).to eq(4)
  end

  it "with a filter on an enum" do
    expect(house_query("energy_grade == 'b'").count).to eq(3)
    expect(house_query("energy_grade != 'd'").count).to eq(9)
  end

  it "with a filter on a bool" do
    expect(house_query("principal == true").count).to eq(6)
    expect(house_query("principal != false").count).to eq(6)
  end

  it "with a filter on a null value" do
    expect(house_query("id != null").count).to eq(10)
  end

  it "with a filter on an association string field" do
    expect(house_query("user.email == 'jason@gmail.com'").count).to eq(5)
    expect(house_query("user.email == 'jASon@gmail.com'").count).to eq(5)
    expect(house_query("user.email === 'jASon@gmail.com'").count).to eq(0)
    expect(house_query("user.email != 'boby@gmail.com'").count).to eq(7)
    expect(house_query("user.email !== 'Boby@gmail.com'").count).to eq(10)
  end

  it "with an ambigous column id" do
    expect(house_query("user.email != 'unknow@gmail.com' && id != null && user.id == '#{jason.id}'").count).to eq(5)
  end

  it "with a filter containing a and logical operator" do
    filter = "street != 'unknown' && street != 'doesntexists' && street == 'street42'"
    expect(house_query(filter).count).to eq(1)
    filter = "street != 'street42' && street != 'doesntexists' && street == 'street42'"
    expect(house_query(filter).count).to eq(0)
    filter = "street != 'street42' && number >= 200"
    expect(house_query(filter).count).to eq(3)
  end

  it "with a filter containing a or logical operator" do
    filter = "street != 'unknown' || street != 'street42'"
    expect(house_query(filter).count).to eq(10)
    filter = "street == 'street1' || street == 'unknown' || street == 'street42'"
    expect(house_query(filter).count).to eq(10)
    filter = "street == 'unknown' || street == 'doesntexists'"
    expect(house_query(filter).count).to eq(0)
  end

  it "with a filter containing useless parenthesis" do
    expect(house_query("(((street != 'unknown') && (((street == null)) || street != 'doesntexists')))").count).to eq(10)
  end

  it "with a blank filter" do
    expect(house_query("").count).to eq(10)
  end

  it "with a complex filter" do
    filter = "(user.email != null && id != \"a078dedc-f757-496f-a9a1-2d632f6ed065\" && (((street != 'unknown') && (((street == null)) || street != 'doesntexists'))))"
    expect(house_query(filter).count).to eq(10)
  end
end
