require 'spec_helper'

describe Bosh::Director::DeploymentPlan::DynamicNetwork do
  before(:each) do
    @deployment_plan = instance_double('Bosh::Director::DeploymentPlan::Planner')
  end

  let(:logger) { Logging::Logger.new('TestLogger') }
  let(:instance) { instance_double(Bosh::Director::DeploymentPlan::Instance) }

  describe '.parse' do
    context 'with a manifest using the old format without explicit subnets' do
      it 'parses the spec and creates a subnet from the dns and cloud properties' do
        network = BD::DeploymentPlan::DynamicNetwork.parse({
            'name' => 'foo',
            'dns' => %w[1.2.3.4 5.6.7.8],
            'cloud_properties' => {
              'foz' => 'baz'
            }
          }, logger)

        expect(network.name).to eq('foo')
        expect(network.subnets.length).to eq(1)
        expect(network.subnets.first.dns).to eq(['1.2.3.4', '5.6.7.8'])
        expect(network.subnets.first.cloud_properties).to eq({'foz' => 'baz'})
      end

      it 'defaults cloud properties to empty hash' do
        network = BD::DeploymentPlan::DynamicNetwork.parse({
            'name' => 'foo',
          }, logger)
        expect(network.subnets.length).to eq(1)
        expect(network.subnets.first.cloud_properties).to eq({})
      end

      it 'defaults dns to nil' do
        network = BD::DeploymentPlan::DynamicNetwork.parse({
            'name' => 'foo',
            'cloud_properties' => {
              'foz' => 'baz'
            }
          }, logger)
        expect(network.subnets.length).to eq(1)
        expect(network.subnets.first.dns).to eq(nil)
      end
    end

    context 'with a manifest specifying subnets' do
      it 'should parse spec' do
        network = BD::DeploymentPlan::DynamicNetwork.parse({
            'name' => 'foo',
            'subnets' => [
              {
                'dns' => %w[1.2.3.4 5.6.7.8],
                'cloud_properties' => {
                  'foz' => 'baz'
                }
              },
              {
                'dns' => %w[9.8.7.6 5.4.3.2],
                'cloud_properties' => {
                  'bar' => 'bat'
                }
              },
            ]
          }, logger)

        expect(network.name).to eq('foo')
        expect(network.subnets.length).to eq(2)
        expect(network.subnets.first.dns).to eq(['1.2.3.4', '5.6.7.8'])
        expect(network.subnets.first.cloud_properties).to eq({'foz' => 'baz'})
        expect(network.subnets.last.dns).to eq(['9.8.7.6', '5.4.3.2'])
        expect(network.subnets.last.cloud_properties).to eq({'bar' => 'bat'})
      end

      it 'defaults cloud properties to empty hash' do
        network = BD::DeploymentPlan::DynamicNetwork.parse({
            'name' => 'foo',
            'subnets' => [
              {
                'dns' => %w[1.2.3.4 5.6.7.8],
              }
            ]
          }, logger)

        expect(network.subnets.length).to eq(1)
        expect(network.subnets.first.cloud_properties).to eq({})
      end

      it 'defaults dns to nil' do
        network = BD::DeploymentPlan::DynamicNetwork.parse({
            'name' => 'foo',
            'subnets' => [
              {
                'cloud_properties' => {
                  'foz' => 'baz'
                }
              },
            ]
          }, logger)

        expect(network.subnets.length).to eq(1)
        expect(network.subnets.first.dns).to eq(nil)
      end

      it 'raises error when dns is present at the top level' do
        expect { BD::DeploymentPlan::DynamicNetwork.parse({
            'name' => 'foo',
            'dns' => %w[1.2.3.4 5.6.7.8],
            'subnets' => [
              {
                'dns' => %w[9.8.7.6 5.4.3.2],
                'cloud_properties' => {
                  'foz' => 'baz'
                }
              },
            ]
          }, logger) }.to raise_error(BD::NetworkInvalidProperty, "top-level 'dns' invalid when specifying subnets")
      end

      it 'raises error when cloud_properties is present at the top level' do
        expect { BD::DeploymentPlan::DynamicNetwork.parse({
            'name' => 'foo',
            'cloud_properties' => {
              'foz' => 'baz'
            },
            'subnets' => [
              {
                'cloud_properties' => {
                  'foz' => 'baz',
                }
              },
            ]
          }, logger) }.to raise_error(BD::NetworkInvalidProperty, "top-level 'cloud_properties' invalid when specifying subnets")

      end
    end
  end

  describe :reserve do
    before(:each) do
      @network = BD::DeploymentPlan::DynamicNetwork.parse({
          'name' => 'foo',
          'cloud_properties' => {
            'foz' => 'baz'
          }
        }, logger)
    end

    it 'should reserve an existing IP' do
      reservation = BD::DynamicNetworkReservation.new(instance, @network)
      reservation.resolve_ip(4294967295)
      @network.reserve(reservation)
      expect(reservation.ip).to eq(4294967295)
    end

    it 'should not let you reserve a static IP' do
      reservation = BD::StaticNetworkReservation.new(instance, @network, '0.0.0.1')

      expect {
        @network.reserve(reservation)
      }.to raise_error BD::NetworkReservationWrongType
    end
  end

  describe :release do
    before(:each) do
      @network = BD::DeploymentPlan::DynamicNetwork.parse({
          'name' => 'foo',
          'cloud_properties' => {
            'foz' => 'baz'
          }
        }, logger)
    end

    it 'should release the IP from the subnet' do
      reservation = BD::DynamicNetworkReservation.new(instance, @network)
      reservation.resolve_ip(4294967295)

      @network.release(reservation)
    end

    it 'should not let you reserve a static IP' do
      reservation = BD::StaticNetworkReservation.new(instance, @network, '0.0.0.1')

      expect {
        @network.reserve(reservation)
      }.to raise_error BD::NetworkReservationWrongType
    end
  end

  describe :network_settings do
    before(:each) do
      @network = BD::DeploymentPlan::DynamicNetwork.parse({
          'name' => 'foo',
          'cloud_properties' => {
            'foz' => 'baz'
          }
        }, logger)
    end

    it 'should provide dynamic network settings' do
      reservation = BD::DynamicNetworkReservation.new(instance, @network)
      reservation.resolve_ip(4294967295)
      expect(@network.network_settings(reservation, [])).to eq({
            'type' => 'dynamic',
            'cloud_properties' => {'foz' => 'baz'},
            'default' => []
          })
    end

    it 'should set the defaults' do
      reservation = BD::DynamicNetworkReservation.new(instance, @network)
      reservation.resolve_ip(4294967295)
      expect(@network.network_settings(reservation)).to eq({
            'type' => 'dynamic',
            'cloud_properties' => {'foz' => 'baz'},
            'default' => ['dns', 'gateway']
          })
    end

    it 'should fail when for static reservation' do
      reservation = BD::StaticNetworkReservation.new(instance, @network, 1)
      expect {
        @network.network_settings(reservation)
      }.to raise_error BD::NetworkReservationWrongType
    end
  end
end
