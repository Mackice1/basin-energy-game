"""V20 fixed-state closed Rankine: real GLPK and independent adversarial audits."""
import copy
import hashlib
import json
import math
import unittest
from unittest import mock
from test_trough_optimizer import backend, GLPK, EPS, device as previous_device, cable, edge


def device(ident, kind, params=None):
    d = previous_device(ident, kind, params)
    if kind in backend.RANKINE_KINDS:
        d['model_profile'] = backend.RANKINE_PROFILE
    return d


def mass_edge(a, b, ak, bk, cap=.05):
    fp, tp, grade = backend.RANKINE_ROUTES[(ak, bk)]
    return {'from': a, 'to': b, 'from_port': fp, 'to_port': tp, 'carrier': 'water_steam',
            'unit': 'kg/s', 'grade_id': grade, 'mass_flow_capacity_kg_s': cap, 'loss_fraction': 0}


def case(generation=.002, demand=1, ambient=25, dt=1):
    return {'schema_version': 5,
            'devices': [device(0,'wind'),device(1,'station',{'capacity_mw':10,'loss_fraction':0}),
                        device(2,'parabolic_trough'),device(3,'steam_generator'),device(4,'steam_turbine'),
                        device(5,'steam_condenser'),device(6,'feedwater_pump'),device(7,'load')],
            'links': [cable(0,1),cable(1,2,boiler=True),cable(1,3,boiler=True),
                      cable(1,5,boiler=True),cable(1,6,boiler=True),
                      dict(cable(4,1),from_port='ac_out',to_port='in',carrier='electricity_ac',unit='MW'),
                      cable(1,7),edge(2,3,'parabolic_trough','steam_generator'),
                      mass_edge(3,4,'steam_generator','steam_turbine'),
                      mass_edge(4,5,'steam_turbine','steam_condenser'),
                      mass_edge(5,6,'steam_condenser','feedwater_pump'),
                      mass_edge(6,3,'feedwater_pump','steam_generator')],
            'steps': [{'time_s':0,'dt_h':dt,'available_mw':{'0':generation},'demand_mw':{'7':demand},
                       'heat_demand_mwth':{},'weather':{'dni_wm2':800,'air_temp_c':ambient,
                           'solar_altitude_deg':90,'solar_azimuth_deg':180}}],
            'options':{'timeout_s':30}}


def with_store(s, initial=.1):
    d=device(8,'high_temp_store',{'self_discharge_per_h':0})
    d['state']={'energy_mwhth':initial}
    s['devices'].append(d)
    s['links'] += [edge(2,8,'parabolic_trough','high_temp_store'),edge(8,3,'high_temp_store','steam_generator')]
    return s


class RankineInputs(unittest.TestCase):
    def test_fixed_state_contract_and_strict_ports(self):
        edits = [lambda s:s.update(schema_version=4),
                 lambda s:s['devices'][3].update(model_profile='high_temp_stage1_v1'),
                 lambda s:s['devices'][3]['params'].update(transfer_efficiency=.98),
                 lambda s:s['devices'][4]['params'].update(generator_efficiency=1),
                 lambda s:s['devices'][5]['params'].update(condensing_temp_c=60),
                 lambda s:s['devices'][5]['params'].update(design_air_temp_c=25),
                 lambda s:s['devices'][6]['params'].update(motor_efficiency=1),
                 lambda s:s['devices'][3]['params'].update(auxiliary_electric_ratio=0),
                 lambda s:s['links'][8].update(carrier='heat_water'),
                 lambda s:s['links'][8].update(unit='MWth'),
                 lambda s:s['links'][8].update(capacity_mwth=.1),
                 lambda s:s['links'][8].update(grade_id='rankine_exhaust_v1'),
                 lambda s:s['links'][8].update(loss_fraction=.1),
                 lambda s:s['links'][8].update(to_port='in'),
                 lambda s:s['links'][7].update(grade_id='hw_primary_90_60'),
                 lambda s:s['links'][5].update(from_port='out'),
                 lambda s:s['links'].append(copy.deepcopy(s['links'][8])),
                 lambda s:s['steps'][0]['weather'].update(air_temp_c=float('nan')),
                 lambda s:s['steps'][0]['available_mw'].update({'4':1})]
        for edit in edits:
            s=case(); edit(s)
            with self.subTest(edit=edit), self.assertRaises(backend.InputError): backend.normalize(s)

    def test_mass_ports_reject_forks_and_shared_components(self):
        for mode in ['sg_fork','shared_turbine','shared_condenser','shared_pump','shared_sg']:
            s=case()
            if mode=='sg_fork':
                s['devices'].append(device(20,'steam_turbine'))
                line=mass_edge(3,20,'steam_generator','steam_turbine')
            elif mode=='shared_turbine':
                s['devices'].append(device(20,'steam_generator'))
                line=mass_edge(20,4,'steam_generator','steam_turbine')
            elif mode=='shared_condenser':
                s['devices'].append(device(20,'steam_turbine'))
                line=mass_edge(20,5,'steam_turbine','steam_condenser')
            elif mode=='shared_pump':
                s['devices'].append(device(20,'steam_condenser'))
                line=mass_edge(20,6,'steam_condenser','feedwater_pump')
            else:
                s['devices'].append(device(20,'feedwater_pump'))
                line=mass_edge(20,3,'feedwater_pump','steam_generator')
            s['links'].append(line)
            with self.subTest(mode=mode),self.assertRaises(backend.InputError):backend.normalize(s)

    def test_mass_capacity_limits_and_preview_is_not_solver_device(self):
        for edit in [lambda s:s['devices'][4]['params'].update(mass_flow_capacity_kg_s=1001),
                     lambda s:s['links'][8].update(mass_flow_capacity_kg_s=1001),
                     lambda s:s['devices'].append({'id':20,'kind':'tower_station_preview'})]:
            s=case();edit(s)
            with self.assertRaises(backend.InputError):backend.normalize(s)

    def test_turbine_paths_exclude_every_conversion_sink(self):
        s=case()
        for ident,kind in [(9,'electric_boiler'),(10,'fuel_boiler'),(11,'solar_thermal'),(12,'oil_water_exchanger')]:
            s['devices'].append(device(ident,kind));s['links'].append(cable(1,ident,boiler=True))
        s['steps'][0]['weather'].update(irradiance_wm2=1000)
        p=backend.normalize(s)
        turbine_paths=[x for x in p['paths'] if x['source']=='4']
        self.assertEqual([x['sink'] for x in turbine_paths],['7'])
        self.assertTrue(all(x['source'] in ['0'] for x in p['paths'] if x['sink'] in ['2','3','5','6','9','10','11','12']))


@unittest.skipUnless(GLPK,'Requires real GLPK')
class RankineOptimizer(unittest.TestCase):
    def solve(self,s):
        original=copy.deepcopy(s);r=backend.solve(s,glpsol=GLPK)
        self.assertTrue(r['success'],r);self.assertEqual(r['status'],'optimal',r)
        self.assertTrue(r['solver_invoked']);self.assertTrue(r['validation']['valid'],r)
        self.assertEqual(s,original)
        return r

    def test_full_chain_mass_energy_and_explicit_rejection(self):
        s=case();r=self.solve(s);row=r['steps'][0];c=row['rankine']
        oil=backend.trough_physics(backend.DEFAULTS['parabolic_trough'],s['steps'][0]['weather'])['available_mwth']
        m=oil*.97/((3008.6-193.238810)/1000)
        self.assertAlmostEqual(c['mass_flow_kg_s'],m,delta=EPS)
        self.assertAlmostEqual(c['oil_input_mwth'],oil,delta=EPS)
        self.assertAlmostEqual(c['gross_electric_mw'],m*(3008.6-2426.78753)*.95/1000,delta=EPS)
        self.assertAlmostEqual(c['condenser_rejection_mwth'],m*(2426.78753-191.81)/1000,delta=EPS)
        self.assertAlmostEqual(c['pump_electric_mw'],m*(193.238810-191.81)/.9/1000,delta=EPS)
        self.assertAlmostEqual(c['auxiliary_electric_mw'],oil*.005+c['condenser_rejection_mwth']*.02+c['pump_electric_mw'],delta=EPS)
        for ident in ['3','4','5','6']:
            self.assertAlmostEqual(row['devices'][ident]['mass_flow_kg_s'],m,delta=EPS)
        for line in row['lines'][8:]:
            self.assertAlmostEqual(line['sent_kg_s'],m,delta=EPS)
            self.assertNotIn('sent_mwth',line);self.assertNotIn('sent_mw',line)
        self.assertAlmostEqual(c['balance_error_mw'],0,delta=EPS)
        self.assertAlmostEqual(row['high_temp']['balance_error_mwth'],0,delta=EPS)
        self.assertAlmostEqual(row['balance_error_mw'],0,delta=EPS)
        self.assertAlmostEqual(row['energy_balance_error_mwh'],0,delta=EPS)
        self.assertAlmostEqual(row['served_mw'],s['steps'][0]['available_mw']['0']+c['net_electric_mw']-oil*.02,delta=EPS)
        self.assertEqual(r['schema_version'],5)
        self.assertAlmostEqual(r['totals']['rankine']['circulated_mass_kg'],m*3600,delta=EPS)

    def test_no_power_no_aux_no_cooling_and_broken_loop_are_dormant(self):
        for mode in ['no_power','no_trough_aux','no_sg_aux','no_cooling_aux','no_pump_aux','no_turbine_cable',
                     'hot_ambient','paused','no_dni','no_sink','no_oil']+[f'broken_{i}' for i in range(8,12)]:
            s=case()
            if mode=='no_power':s['steps'][0]['available_mw']['0']=0
            if mode in ['no_trough_aux','no_sg_aux','no_cooling_aux','no_pump_aux','no_turbine_cable']:
                s['links'].pop(['no_trough_aux','no_sg_aux','no_cooling_aux','no_pump_aux','no_turbine_cable'].index(mode)+1)
            if mode=='hot_ambient':s['steps'][0]['weather']['air_temp_c']=35.806
            if mode=='paused':s['steps'][0]['dt_h']=0
            if mode=='no_dni':s['steps'][0]['weather']['dni_wm2']=0
            if mode=='no_sink':s['steps'][0]['demand_mw']['7']=0
            if mode=='no_oil':s['links'].pop(7)
            if mode.startswith('broken_'):s['links'].pop(int(mode.split('_')[1]))
            with self.subTest(mode=mode):
                row=self.solve(s)['steps'][0]
                self.assertAlmostEqual(row['rankine']['mass_flow_kg_s'],0,delta=EPS)
                self.assertAlmostEqual(row['rankine']['gross_electric_mw'],0,delta=EPS)

    def test_each_resource_bottleneck_is_atomic(self):
        for mode in ['steam_edge','exhaust_edge','condensate_edge','feed_edge','sg','turbine','pump','condenser','sg_ac','cond_ac','pump_ac','external_source','station']:
            s=case(generation=.1);m=.003;c=backend.rankine_coefficients();oil=m*c['steam_heat']/.97
            aux=oil*.025+m*c['rejection']*.02+m*c['pump_work']/.9
            if mode.endswith('_edge'):s['links'][8+['steam_edge','exhaust_edge','condensate_edge','feed_edge'].index(mode)]['mass_flow_capacity_kg_s']=m
            if mode=='sg':s['devices'][3]['params']['capacity_mwth']=oil
            if mode in ['turbine','pump']:s['devices'][4 if mode=='turbine' else 6]['params']['mass_flow_capacity_kg_s']=m
            if mode=='condenser':s['devices'][5]['params']['capacity_mwth']=m*c['rejection']
            if mode=='sg_ac':s['links'][2]['capacity_mw']=oil*.005
            if mode=='cond_ac':s['links'][3]['capacity_mw']=m*c['rejection']*.02
            if mode=='pump_ac':s['links'][4]['capacity_mw']=m*c['pump_work']/.9
            if mode=='external_source':s['steps'][0]['available_mw']['0']=aux
            if mode=='station':
                # External auxiliaries and turbine gross share the same station cap.
                s['devices'][1]['params']['capacity_mw']=aux+m*c['shaft']*.95
                s['steps'][0]['available_mw']['0']=aux
            with self.subTest(mode=mode):
                row=self.solve(s)['steps'][0]
                self.assertAlmostEqual(row['rankine']['mass_flow_kg_s'],m,delta=EPS)

    def test_ambient_derating_is_recomputed_and_blocks_hot_sink(self):
        s=with_store(case(generation=.1,ambient=30),initial=.2)
        s['devices'][5]['params']['capacity_mwth']=.04
        row=self.solve(s)['steps'][0]
        cap=.04*(45.806-30)/(45.806-25)
        self.assertAlmostEqual(row['rankine']['condenser_rejection_mwth'],cap,delta=EPS)
        self.assertAlmostEqual(row['devices']['5']['available_rejection_mwth'],cap,delta=EPS)
        s['steps'][0]['weather']['air_temp_c']=35.806
        self.assertAlmostEqual(self.solve(s)['steps'][0]['rankine']['mass_flow_kg_s'],0,delta=EPS)

    def test_night_oil_storage_requires_external_auxiliaries(self):
        s=with_store(case());s['steps'][0]['weather']['dni_wm2']=0
        row=self.solve(s)['steps'][0]
        self.assertGreater(row['rankine']['gross_electric_mw'],0)
        self.assertAlmostEqual(row['high_temp']['discharge_mwth'],row['rankine']['oil_input_mwth'],delta=EPS)
        s['steps'][0]['available_mw']['0']=0
        row=self.solve(s)['steps'][0]
        self.assertAlmostEqual(row['rankine']['mass_flow_kg_s'],0,delta=EPS)
        self.assertAlmostEqual(row['high_temp']['energy_mwhth'],.1,delta=EPS)

    def test_explicit_export_and_battery_charging_are_turbine_sinks(self):
        for sink in ['grid','battery']:
            s=case(demand=0)
            if sink=='grid':s['links'].append(cable(1,-1))
            else:
                b=device(9,'battery',{'initial_soc':0});b['state']={'energy_mwh':0};s['devices'].append(b)
                s['links'].append(cable(1,9))
                s['options']['terminal_soc_fraction']=.0005
            with self.subTest(sink=sink):
                row=self.solve(s)['steps'][0]
                self.assertGreater(row['rankine']['gross_electric_mw'],0)
                self.assertGreater(row['export_mw'] if sink=='grid' else row['charge_mw'],0)

    def test_external_battery_aux_is_finite_and_no_same_step_charge_discharge(self):
        s=case(generation=0);b=device(9,'battery',{'capacity_mwh':.01,'initial_soc':.1});b['state']={'energy_mwh':.001}
        s['devices'].append(b);s['links'].append(cable(1,9));r=self.solve(s);row=r['steps'][0]
        self.assertGreater(row['rankine']['gross_electric_mw'],0)
        self.assertEqual(row['devices']['9']['mode'],'discharge')
        self.assertAlmostEqual(row['devices']['9']['charge_mw'],0,delta=EPS)
        self.assertLessEqual(row['devices']['9']['discharge_mw'],.0009+EPS)
        s['devices'][-1]['state']['energy_mwh']=0
        self.assertAlmostEqual(self.solve(s)['steps'][0]['rankine']['mass_flow_kg_s'],0,delta=EPS)

    def test_shared_oil_with_old_heat_service_is_not_double_counted(self):
        s=case(generation=.1)
        s['devices'] += [device(9,'oil_water_exchanger'),device(10,'heat_exchanger'),device(11,'heat_demand')]
        s['links'] += [cable(1,9,boiler=True),edge(2,9,'parabolic_trough','oil_water_exchanger'),
                      edge(9,10,'oil_water_exchanger','heat_exchanger'),edge(10,11,'heat_exchanger','heat_demand')]
        s['steps'][0]['heat_demand_mwth']={'11':.02}
        row=self.solve(s)['steps'][0]
        self.assertAlmostEqual(row['high_temp']['useful_mwth'],row['rankine']['oil_input_mwth']+row['devices']['9']['input_mwth'],delta=EPS)
        self.assertGreater(row['thermal']['served_mwth'],0)
        self.assertGreater(row['rankine']['gross_electric_mw'],0)

    def test_report_tampering_is_rejected_despite_zero_residual(self):
        s=case();p=backend.normalize(s);r=self.solve(s)
        edits=[lambda row:row['rankine'].update(balance_error_mw=.1),
               lambda row:row['rankine'].update(gross_electric_mw=1,balance_error_mw=0),
               lambda row:row['devices']['3'].update(mass_flow_kg_s=1),
               lambda row:row['devices']['3'].update(auxiliary_electric_mw=0),
               lambda row:row['devices']['4'].update(generator_loss_mw=0),
               lambda row:row['devices']['5'].update(condenser_rejection_mwth=0),
               lambda row:row['devices']['5'].update(available_rejection_mwth=10),
               lambda row:row['devices']['6'].update(pump_motor_loss_mw=0),
               lambda row:row['lines'][8].update(sent_kg_s=.02),
               lambda row:row['lines'][8].update(enthalpy_kj_kg=1),
               lambda row:row['lines'][8].update(enthalpy_flow_mw=1),
               lambda row:row['lines'][8].update(grade_id='rankine_feedwater_v1'),
               lambda row:row['path_flows'][0].update(source_id=4),
               lambda row:row['lines'][5].update(flow_from=0),
               lambda row:row['lines'][5].update(flow_from=1,flow_to=4),
               lambda row:row['mass_flows'][0].update(sent_kg_s=.02),
               lambda row:row['high_temp'].update(rankine_oil_input_mwth=0)]
        for edit in edits:
            rows=copy.deepcopy(r['steps']);edit(rows[0])
            with self.subTest(edit=edit):self.assertFalse(backend.validate_schedule(p,rows)['valid'])

    def test_bad_lp_generation_and_auxiliary_rows_fail_physical_audit(self):
        original=backend.build_model
        def corrupt(p):
            m=original(p)
            for terms,rel,rhs in m.rows:
                if 'rankine_0_4' in terms and any(k.startswith('x_') for k in terms):
                    terms['rankine_0_4']*=2
            return m
        with mock.patch.object(backend,'build_model',side_effect=corrupt):r=backend.solve(case(),glpsol=GLPK)
        self.assertFalse(r['success']);self.assertTrue(r['solver_invoked'])

    def test_two_cycles_share_atomic_external_power_and_station(self):
        s=case(generation=.0006)
        s['devices'][4]['params']['mass_flow_capacity_kg_s']=.003
        for ident,kind in [(13,'steam_generator'),(14,'steam_turbine'),(15,'steam_condenser'),(16,'feedwater_pump')]:
            s['devices'].append(device(ident,kind,{'mass_flow_capacity_kg_s':.003} if kind=='steam_turbine' else {}))
        s['links'] += [cable(1,13,boiler=True),cable(1,15,boiler=True),cable(1,16,boiler=True),
                      dict(cable(14,1),from_port='ac_out'),edge(2,13,'parabolic_trough','steam_generator'),
                      mass_edge(13,14,'steam_generator','steam_turbine'),mass_edge(14,15,'steam_turbine','steam_condenser'),
                      mass_edge(15,16,'steam_condenser','feedwater_pump'),mass_edge(16,13,'feedwater_pump','steam_generator')]
        c=backend.rankine_coefficients();aux_per_mass=c['steam_heat']/.97*.025+c['rejection']*.02+c['pump_work']/.9
        row=self.solve(s)['steps'][0]
        self.assertAlmostEqual(row['rankine']['mass_flow_kg_s'],.0006/aux_per_mass,delta=EPS)
        self.assertGreater(row['devices']['4']['mass_flow_kg_s'],0)
        self.assertGreater(row['devices']['14']['mass_flow_kg_s'],0)
        self.assertAlmostEqual(row['rankine']['auxiliary_electric_mw']+row['high_temp']['collector_auxiliary_electric_mw'],.0006,delta=EPS)
        s['devices'][1]['params']['capacity_mw']=.0008
        row=self.solve(s)['steps'][0]
        self.assertLessEqual(row['devices']['1']['input_mw'],.0008+EPS)
        self.assertLess(row['rankine']['mass_flow_kg_s'],.0006/aux_per_mass)

    def test_long_cross_connected_eight_node_loop_is_dormant(self):
        s=case(generation=.1)
        for ident,kind in [(13,'steam_generator'),(14,'steam_turbine'),(15,'steam_condenser'),(16,'feedwater_pump')]:
            s['devices'].append(device(ident,kind))
        s['links'][-1]['to']=13
        s['links'] += [cable(1,13,boiler=True),cable(1,15,boiler=True),cable(1,16,boiler=True),
                      dict(cable(14,1),from_port='ac_out'),edge(2,13,'parabolic_trough','steam_generator'),
                      mass_edge(13,14,'steam_generator','steam_turbine'),mass_edge(14,15,'steam_turbine','steam_condenser'),
                      mass_edge(15,16,'steam_condenser','feedwater_pump'),mass_edge(16,3,'feedwater_pump','steam_generator')]
        row=self.solve(s)['steps'][0]
        self.assertAlmostEqual(row['rankine']['gross_electric_mw'],0,delta=EPS)
        self.assertTrue(all(abs(row['devices'][str(k)]['mass_flow_kg_s'])<EPS for k in [3,4,5,6,13,14,15,16]))

    def test_source_line_station_and_auxiliary_losses_balance(self):
        s=case(generation=.002)
        for line in s['links']:
            if 'capacity_mw' in line:line['loss_fraction']=.1
        s['devices'][1]['params']['loss_fraction']=.1
        row=self.solve(s)['steps'][0];c=row['rankine']
        self.assertGreater(c['gross_electric_mw'],0)
        self.assertAlmostEqual(row['produced_mw'],row['served_mw']+c['auxiliary_electric_mw']+row['high_temp']['collector_auxiliary_electric_mw']+row['loss_mw'],delta=EPS)
        self.assertAlmostEqual(row['balance_error_mw'],0,delta=EPS)
        self.assertAlmostEqual(row['energy_balance_error_mwh'],0,delta=EPS)
        self.assertGreater(row['line_loss_mw'],0);self.assertGreater(row['station_loss_mw'],0)

    def test_day_charge_then_night_generation_respects_oil_inventory(self):
        s=with_store(case(generation=.002,demand=0),initial=0)
        next_step=copy.deepcopy(s['steps'][0]);next_step.update(time_s=3600,demand_mw={'7':1})
        next_step['weather']['dni_wm2']=0;s['steps'].append(next_step)
        r=self.solve(s);day,night=r['steps']
        self.assertGreater(day['high_temp']['charge_mwth'],0)
        self.assertAlmostEqual(day['rankine']['gross_electric_mw'],0,delta=EPS)
        self.assertGreater(night['rankine']['gross_electric_mw'],0)
        self.assertAlmostEqual(night['rankine']['oil_input_mwth'],day['high_temp']['charge_mwth']*.98**2,delta=EPS)
        self.assertAlmostEqual(night['high_temp']['energy_mwhth'],0,delta=EPS)
        for row in r['steps']:
            self.assertAlmostEqual(row['high_temp']['energy_balance_error_mwhth'],0,delta=EPS)
            self.assertAlmostEqual(row['energy_balance_error_mwh'],0,delta=EPS)

    def test_corrupt_auxiliary_row_and_cooling_bound_fail_independent_audit(self):
        original=backend.build_model
        for mode in ['auxiliary','cooling']:
            def corrupt(p):
                m=original(p)
                if mode=='auxiliary':
                    for terms,rel,rhs in m.rows:
                        if 'rankine_0_6' in terms and any(k.startswith('x_') for k in terms):terms['rankine_0_6']*=10
                else:
                    m.bounds['rankine_0_5']=(0,1)
                return m
            s=with_store(case(generation=.1,ambient=35.806),initial=.2) if mode=='cooling' else case()
            with self.subTest(mode=mode),mock.patch.object(backend,'build_model',side_effect=corrupt):
                r=backend.solve(s,glpsol=GLPK)
                self.assertFalse(r['success']);self.assertTrue(r['solver_invoked'])

    def test_corrupt_path_allows_no_turbine_to_auxiliary_bootstrap(self):
        original=backend.build_model
        def corrupt(p):
            source=next(x for x in p['paths'] if x['source']=='4')
            sink=next(x for x in p['paths'] if x['sink']=='3')
            forged=dict(source,sink='3',outgoing=sink['outgoing'])
            p['paths'].append(forged)
            return original(p)
        with mock.patch.object(backend,'build_model',side_effect=corrupt):
            r=backend.solve(case(),glpsol=GLPK)
        self.assertFalse(r['success']);self.assertTrue(r['solver_invoked'])

    def test_horizon_totals_dimensional_consistency_and_no_live_mutation(self):
        s=with_store(case(generation=.003,dt=.25),initial=.1)
        for i in range(1,5):
            st=copy.deepcopy(s['steps'][0]);st['time_s']=i*900
            st['weather']['air_temp_c']=25+i*2;st['available_mw']['0']=.001+i*.0002
            s['steps'].append(st)
        original=copy.deepcopy(s);r=self.solve(s)
        self.assertEqual(original,s)
        for field,value in r['totals']['rankine'].items():
            source=field.replace('_mwh','_mw')
            if field=='circulated_mass_kg':expected=sum(row['rankine']['mass_flow_kg_s']*row['dt_h']*3600 for row in r['steps'])
            else:expected=sum(row['rankine'][source]*row['dt_h'] for row in r['steps'])
            self.assertAlmostEqual(value,expected,delta=EPS)
        self.assertAlmostEqual(r['totals']['rankine']['balance_error_mwh'],0,delta=EPS)

    def test_v19_reports_remain_bytewise_identical(self):
        from test_trough_optimizer import case as old_case,store
        fixtures=[(old_case(),'9a2cdfb23202e8c72c6ab853bd5f69b093d19c488e7a8bc656ce02fde9a5bc83'),
                  (store(old_case()),'9c7542a8c648873e423db653e91a222508c478dc361e49f3dd1c3c68bcea3363'),
                  (store(old_case(demand=0),.1),'e5563b86fd7e51bf1a8ac3152aa4c9e8f513be48afe82368060cecea1add96dc')]
        for s,expected in fixtures:
            r=self.solve(s);r.pop('elapsed_s');r.pop('solver_stages')
            self.assertEqual(hashlib.sha256(json.dumps(r,separators=(',',':'),ensure_ascii=False).encode()).hexdigest(),expected)

if __name__=='__main__':unittest.main()
