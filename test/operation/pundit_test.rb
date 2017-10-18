require "test_helper"
require "trailblazer/operation/policy"

class PolicyTest < Minitest::Spec
  Song = Struct.new(:id) do
    def self.find(id); new(id) end
  end

  class Auth
    def initialize(user, model); @user, @model = user, model end
    def only_user?; @user == Module && @model.nil? end
    def user_object?; @user == Object end
    def user_and_model?; @user == Module && @model.class == Song end
    def inspect; "<Auth: user:#{@user.inspect}, model:#{@model.inspect}>" end
  end

  #---
  # Instance-level: Only policy, no model
  class Create < Trailblazer::Operation
    step Policy::Pundit( Auth, :only_user? )
    step :process

    def process(*)
      self["process"] = true
    end
  end

  # successful.
  it do
    result = Create.({}, "current_user" => Module)
    result["process"].must_equal true
    #- result object, policy
    result["result.policy.default"].success?.must_equal true
    result["result.policy.default"]["message"].must_equal nil
    # result[:valid].must_equal nil
    result["policy.default"].inspect.must_equal %{<Auth: user:Module, model:nil>}
  end
  # breach.
  it do
    result = Create.({}, "current_user" => nil)
    result["process"].must_equal nil
    #- result object, policy
    result["result.policy.default"].success?.must_equal false
    result["result.policy.default"]["message"].must_equal "Breach"
  end
  # inject different policy.Condition  it { Create.({}, "current_user" => Object, "policy.default.eval" => Trailblazer::Operation::Policy::Pundit::Condition.new(Auth, :user_object?))["process"].must_equal true }
  it { Create.({}, "current_user" => Module, "policy.default.eval" => Trailblazer::Operation::Policy::Pundit::Condition.new(Auth, :user_object?))["process"].must_equal nil }


  #---
  # inheritance, adding Model
  class Show < Create
    step Model( Song, :new ), before: "policy.default.eval"
  end

  it { Show["pipetree"].inspect.must_equal %{[>operation.new,>model.build,>policy.default.eval,>process]} }

  # invalid because user AND model.
  it do
    result = Show.({}, "current_user" => Module)
    result["process"].must_equal nil
    result["model"].inspect.must_equal %{#<struct PolicyTest::Song id=nil>}
    # result["policy"].inspect.must_equal %{#<struct PolicyTest::Song id=nil>}
  end

  # valid because new policy.
  it do
    # puts Show["pipetree"].inspect
    result = Show.({}, "current_user" => Module, "policy.default.eval" => Trailblazer::Operation::Policy::Pundit::Condition.new(Auth, :user_and_model?))
    result["process"].must_equal true
    result["model"].inspect.must_equal %{#<struct PolicyTest::Song id=nil>}
    result["policy.default"].inspect.must_equal %{<Auth: user:Module, model:#<struct PolicyTest::Song id=nil>>}
  end

  ##--
  # TOOOODOOO: Policy and Model before Build ("External" or almost Resolver)
  class Edit < Trailblazer::Operation
    step Model Song, :find
    step Policy::Pundit( Auth, :user_and_model? )
    step :process

    def process(*); self["process"] = true end
  end

  # successful.
  it do
    result = Edit.({ id: 1 }, "current_user" => Module)
    result["process"].must_equal true
    result["model"].inspect.must_equal %{#<struct PolicyTest::Song id=1>}
    result["result.policy.default"].success?.must_equal true
    result["result.policy.default"]["message"].must_equal nil
    # result[:valid].must_equal nil
    result["policy.default"].inspect.must_equal %{<Auth: user:Module, model:#<struct PolicyTest::Song id=1>>}
  end

  # breach.
  it do
    result = Edit.({ id: 4 }, "current_user" => nil)
    result["model"].inspect.must_equal %{#<struct PolicyTest::Song id=4>}
    result["process"].must_equal nil
    result["result.policy.default"].success?.must_equal false
    result["result.policy.default"]["message"].must_equal "Breach"
  end


  class TeamPolicy

    attr_reader :record

    def initialize(user, record)
      @user   = user
      @record = record
    end

    def index?; true; end
  end

  class Team; end;

  class Team::Index < Trailblazer::Operation
    step :set_pundit_record_context!
    step Policy::Pundit(TeamPolicy, :index?)
    failure :policy_failed
    step :set_model!

    def set_pundit_record_context!(options, params:, **)
      organization = OpenStruct.new(id: params[:organization_id], teams: [])
      options['pundit.record'] = organization
    end

    def set_model!(options, **)
      options['model'] = options['pundit.record'].teams
    end
  end

  it 'should initialize pundit policy with pundit.record' do
    result = Team::Index.({ organization_id: 4711 }, "current_user" => Module)

    result['policy.default'].record.id.must_equal 4711
    result['result.policy.default'].success?.must_equal true
  end

end
