#!/usr/bin/env ruby
# vim: set et sw=2 ts=2 nowrap:
require 'rubygems'
require 'date'
require 'iconv'
require 'yaml'

module Payments
  class PaymentParser
    def initialize(lines=nil, config=nil)
      @config = config
      @config ||= YAML.load_file(File.dirname(__FILE__)+'/config.yaml')
      raise 'Config file not readable and config not provided' unless @config
      @_pattern = _prepare_pattern()
      read_lines(lines)
    end

    def read_lines(lines)
      @_accounts = nil
      @_payments = nil
      @_payments_by_month = nil
      
      return unless lines

      _payments = _parse_payment_lines(lines)
      # filter out unrelated payments
      if accounts
        @_payments = _payments.select { |p| accounts[p['acc']] }
      else
        @_payments = _payments
      end
    end

    def payments_by_month()
      if @_payments_by_month.nil? and accounts
        # group my months
        @_payments_by_month = group_payments(@_payments) { |p| '%04d-%02d' % [p['date'].year, p['date'].month] }
        # set calculated diff between payment and expected value
        @_payments_by_month.each { |m,payments|
          payments.each { |acc_num, p|
            expected = expected_amount( accounts[acc_num], m)
            p['expected'] = expected
            p['diff'] = p['amount'] - expected
          }
        }
      end

      return @_payments_by_month
    end

    def accounts()
      if @_accounts.nil?
        @_accounts = {}
        @config['payments']['accounts'].each { |acc_cfg|
          @_accounts[ acc_cfg['number'] ] = _prepare_account(acc_cfg)
        }
      end

      return @_accounts
    end

    def group_payments(payments, &group_key)
      grouped = {}
      payments.each { |p|
        acc = p['acc']
        amount = p['amount']
        key = group_key.call(p)
        nan = 0.0 / 0.0

        grouped[key] = {} unless grouped[key]
        if grouped[key][acc]
          grouped[key][acc]['amount'] += amount
          grouped[key][acc]['cnt'] += 1
        else
          grouped[key][acc] = {'acc'=>acc, 'amount'=>amount, 'cnt'=>1, 'diff'=>nan}
        end
      }
      return grouped
    end

    def expected_amount(account, year_month)
      default_expected = (account['amounts'].select { |exp_am| exp_am['due'].nil? }).first
      amount = default_expected['value']

      happened_at = Date.parse(year_month+'-01')
      oldest_match = nil

      account['amounts'].each { |exp_am|
        next if exp_am['due'].nil?

        if happened_at <= exp_am['due'] and (oldest_match.nil? or exp_am['due'] < oldest_match)
          oldest_match = exp_am['due']
          amount = exp_am['value']
        end
      }
      return amount
    end

    def diff_in_payment(payment, month)
      return payment['amount'] - expected_amount(accounts[payment['acc']], month)
    end

    def _prepare_account(acc_cfg)
        acc = {'name'=>acc_cfg['name'], 'note'=>'', 'amounts'=>[]}
        if acc_cfg['note']:
          acc['note'] = acc_cfg['note']
        end
        acc_cfg['amounts'].each { |am_cfg|
          am = {'value'=>am_cfg['value']}
          if am_cfg['due_month']
            am['due'] = Date.parse(am_cfg['due_month']+'-01')
          end
          acc['amounts'] << am
        }
        return acc
    end
    
    def _prepare_pattern()
      date = '[0-9]{2}-[0-9]{2}-[0-9]{4}'
      type = 'PŘÍCHOZÍ PLATBA[^;]+'
      str = '[^;]*'
      msg = str
      from_name = str
      from_acc = "[0-9/-]+"
      ks = '[0-9]*'
      vs = '[0-9]*'
      amount = '[0-9]+,[0-9]+'
      
      pattern = [
        "(#{date});", #1
        "(#{date});", #2
        "(#{type});", #3
        "\"(#{msg})\";", #4
        "\"(#{from_name})\";", #5
        "\'(#{from_acc})\';", #6
        "(#{ks});", #7
        "(#{vs});", #8
        ";", 
        "(#{amount})" #9
      ]

      return Regexp.compile(
        pattern.join('')
      )
    end

    def _line_to_info(line_parts)
      info = {}
      info['date'] = Date.parse(line_parts[1])
      info['name'] = line_parts[5]
      info['acc'] = line_parts[6]
      info['ks'] = line_parts[7]
      info['vs'] = line_parts[8]
      info['amount'] = line_parts[9]

      info['amount'][','] = '.'
      info['amount'] = info['amount'].to_f
      return info
    end

    def _parse_payment_lines(lines)
      payments = []
      lines.each { |line|
        line = Iconv.iconv('utf-8', 'cp1250', line)
        line = line[0]
        parts = @_pattern.match(line)
        next unless parts
        payments << _line_to_info(parts)
      }
      return payments
    end
  end # endOf class PaymentParser
end # endOf module Payments

