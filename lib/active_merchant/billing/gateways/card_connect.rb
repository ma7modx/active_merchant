module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class CardConnectGateway < Gateway
      self.test_url = 'https://example.com/test'
      self.live_url = 'https://example.com/live'

      self.supported_countries = ['US']
      self.default_currency = 'USD'
      self.supported_cardtypes = [:visa, :master, :american_express, :discover]

      self.homepage_url = 'https://cardconnect.com/'
      self.display_name = 'Card Connect'

      STANDARD_ERROR_CODE_MAPPING = {}

      def initialize(options={})
        requires!(options, :merchant_id, :username, :password)
        super
      end

      def purchase(money, payment, options={})
        post = {}
        add_invoice(post, money, options)
        add_payment(post, payment)
        add_address(post, payment, options)
        add_customer_data(post, options)

        if options[:purchase_order]
          post[:capture] = "Y"
          commit('authorize', post)
        else
          add_additional_data(post, options)
          MultiResponse.run(:use_first_response) do |r|
            r.process { authorize(amount, payment, options) }
            r.process { capture(amount, r.authorization, options) }
          end
        end
      end

      def authorize(money, payment, options={})
        post = {}
        post[:tokenize] = "Y"
        add_invoice(post, money, options)
        add_payment(post, payment)
        add_address(post, payment, options)
        add_customer_data(post, options)

        commit('authonly', post)
      end

      def capture(money, authorization, options={})
        post = {}
        add_reference(post, authorization)
        commit('capture', post)
      end

      def refund(money, authorization, options={})
        post = {}
        add_reference(post, authorization)
        commit('refund', post)
      end

      def void(authorization, options={})
        post = {}
        add_reference(post, authorization)
        commit('void', post)
      end

      def verify(credit_card, options={})
        MultiResponse.run(:use_first_response) do |r|
          r.process { authorize(100, credit_card, options) }
          r.process(:ignore_result) { void(r.authorization, options) }
        end
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript
      end

      private
      
      ACTIONS = {
        "authorize" => "auth",
        "authonly" => "auth",
        "capture" => "capture",
        "void" => "void",
        "refund" => "refund"
      }

      def add_customer_data(post, options)
        post[:email] = options[:email] if options[:email]
      end

      def add_address(post, creditcard, options)
        if address = options[:billing_address] || options[:address]
          post[:address] = address[:address1] if address[:address1]
          post[:city] = address[:city] if address[:city]
          post[:region] = address[:state] if address[:state]
          post[:country] = address[:country] if address[:country]
          post[:postal] = address[:zip] if address[:zip]
          post[:phone] = address[:phone] if address[:phone]
        end
      end

      def add_invoice(post, money, options)
        post[:amount] = amount(money)
        post[:currency] = (options[:currency] || currency(money))
        post[:ecomind] = (options[:recurring] ? "R" : "E") 
      end

      def add_payment(post, payment)
        post[:name] = payment.name
        if card_brand(payment_method) == 'check'
          add_echeck(post, payment)
        else
          post[:account] = payment.number
          post[:expiry] = expdate(payment)
          post[:cvv2] = payment.verification_value
        end
      end

      def add_echeck(post, payment)
        post[:accttype] = "ECHK"
        post[:account] = payment.account_number
        post[:bankaba] = payment.routing_number
      end
      
      def add_reference(post, authorization)
        post[:retref] = authorization
      end

      def add_additional_data(post, options)
        post[:ponumber] = options[:purchase_number]
        post[:taxamnt] = options[:tax_amount] if options[:tax_amount]
        post[:frtamnt] = options[:freight_amount] if options[:freight_amount]
        post[:dutyamnt] = options[:duty_amount] if options[:duty_amount]
        post[:orderdate] = option[:order_date] if option[:order_date]
        post[:shipfromzip] = option[:ship_from_zip] if option[:ship_from_zip]
        if (shipping_address = options[:shipping_address])
          post[:shiptozip] = shipping_address[:zip]
          post[:shiptocountry] = shipping_address[:country]
        end
        if options[:line_items]
          post[:items] = []
          post[:line_items].each do | line_item |
            updated = {}
            line_item.each_pair do |k,v|
              updated.merge!({k.tr('_', '') => v})
            end
            post[:items] << updated
          end
        end
      end

      def expdate(credit_card)
        "#{format(credit_card.month, :two_digits)}#{format(credit_card.year, :two_digits)}"
      end

      def parse(body)
        JSON.parse(body)
      end

      def url(action)
        url = (test? ? test_url : live_url) + ACTIONS[action]
      end

      def commit(action, parameters)
        post[:merchid] = @options[:merchant_id]
        url = (test? ? test_url : live_url)
        response = parse(ssl_post(url, post_data(action, parameters)))

        Response.new(
          success_from(response),
          message_from(response),
          response,
          authorization: authorization_from(response),
          avs_result: AVSResult.new(code: response["some_avs_response_key"]),
          cvv_result: CVVResult.new(response["some_cvv_response_key"]),
          test: test?,
          error_code: error_code_from(response)
        )
      end

      def success_from(response)
        response["respstat"] == "A"
      end

      def message_from(response)
        response["setlstat"] ? "#{response["resptext"]} #{response["setlstat"]}" : response["resptext"]
      end

      def authorization_from(response)
        response["token"]
      end

      def post_data(action, parameters = {})
      end

      def error_code_from(response)
        unless success_from(response)
          # TODO: lookup error code for this response
        end
      end
    end
  end
end
