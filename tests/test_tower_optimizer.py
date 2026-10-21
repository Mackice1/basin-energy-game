"""V21 salt-grade tower: real GLPK dispatch and independent conservation audits."""
import copy
import math
import unittest
from unittest import mock
from test_rankine_optimizer import backend, GLPK, EPS, cable, mass_edge


def device(ident, kind, params=None):
    result = {'id': ident, 'kind': kind, 'params': params or {}}
    if kind in backend.THERMAL_KINDS:
        result.update(model_profile=backend.rankine_profile(kind), model_profile_version=1)
    return result


def edge(a, b, ak, bk, cap=1.):
    fp,tp,grade=backend.THERMAL_ROUTES[(ak,bk)]
    return dict(from_port=fp,to_port=tp,carrier='heat_salt',unit='MWth',grade_id=grade,
                capacity_mwth=cap,loss_fraction=0,**{'from':a,'to':b})


def case(generation=.02, demand=1., initial=0., night=False, dt=1.):
    s={'schema_version':6,
       'devices':[device(0,'wind'),device(1,'station',{'capacity_mw':10,'loss_fraction':0}),
                  device(2,'solar_tower_receiver'),device(3,'salt_steam_generator'),
                  device(4,'steam_turbine'),device(5,'steam_condenser'),device(6,'feedwater_pump'),
                  device(7,'load'),device(8,'molten_salt_store')],
       'links':[cable(0,1),cable(1,2,boiler=True),cable(1,3,boiler=True),cable(1,5,boiler=True),
                cable(1,6,boiler=True),dict(cable(4,1),from_port='ac_out',to_port='in',carrier='electricity_ac',unit='MW'),
                cable(1,7),cable(1,8,boiler=True),
                edge(2,3,'solar_tower_receiver','salt_steam_generator'),
                edge(2,8,'solar_tower_receiver','molten_salt_store'),
                edge(8,3,'molten_salt_store','salt_steam_generator'),
                mass_edge(3,4,'salt_steam_generator','steam_turbine'),
                mass_edge(4,5,'steam_turbine','steam_condenser'),
                mass_edge(5,6,'steam_condenser','feedwater_pump'),
                mass_edge(6,3,'feedwater_pump','salt_steam_generator')],
       'steps':[{'time_s':0,'dt_h':dt,'available_mw':{'0':generation},'demand_mw':{'7':demand},
                 'heat_demand_mwth':{},'weather':{'dni_wm2':800,'solar_altitude_deg':-10 if night else 50,
                    'solar_azimuth_deg':180,'air_temp_c':25,'is_day':not night}}],
       'options':{'timeout_s':30}}
    s['devices'][8]['state']={'energy_mwhth':initial}
    return s


class TowerInputs(unittest.TestCase):
    def test_equivalent_optics_and_shared_daylight_gate(self):
        s=case();w=s['steps'][0]['weather'];p=backend.DEFAULTS['solar_tower_receiver']
        physics=backend.tower_physics(p,w)
        self.assertAlmostEqual(physics['available_mwth'],800*1600*.6*.9/1e6)
        for edits in [{'is_day':False},{'solar_altitude_deg':0},{'solar_altitude_deg':-20}]:
            self.assertEqual(backend.tower_physics(p,dict(w,**edits))['available_mwth'],0)
        self.assertAlmostEqual(physics['incident_mw'],physics['optical_rejection_mw']+physics['thermal_loss_mw']+physics['available_mwth'])

    def test_strict_schema_weather_grade_and_fixed_area(self):
        edits=[lambda s:s.update(schema_version=5),
               lambda s:s['devices'][2]['params'].update(mirror_area_m2=1601),
               lambda s:s['devices'][2].update(model_profile=backend.HIGH_TEMP_PROFILE),
               lambda s:s['devices'][8].update(state={'energy_mwh':.1}),
               lambda s:s['links'][8].update(carrier='heat_oil'),
               lambda s:s['links'][8].update(grade_id=backend.OIL_GRADE),
               lambda s:s['links'][8].update(to_port='oil_in'),
               lambda s:s['links'][8].update(loss_fraction=.1),
               lambda s:s['steps'][0].update(tower_available_mwth={'2':1})]
        for field in ['dni_wm2','solar_altitude_deg','solar_azimuth_deg','air_temp_c','is_day']:
            edits.append(lambda s,f=field:s['steps'][0]['weather'].pop(f))
        for edit in edits:
            s=case();edit(s)
            with self.subTest(edit=edit),self.assertRaises(backend.InputError):backend.normalize(s)

    def test_auxiliary_provenance_excludes_turbines(self):
        p=backend.normalize(case())
        self.assertEqual([x['sink'] for x in p['paths'] if x['source']=='4'],['7'])
        self.assertTrue(all(x['source']=='0' for x in p['paths'] if x['sink'] in ['2','3','5','6','8']))


@unittest.skipUnless(GLPK,'Requires real GLPK')
class TowerOptimizer(unittest.TestCase):
    def solve(self,s):
        original=copy.deepcopy(s);r=backend.solve(s,glpsol=GLPK)
        self.assertTrue(r['success'],r);self.assertEqual(r['status'],'optimal',r)
        self.assertTrue(r['solver_invoked']);self.assertTrue(r['validation']['valid'],r)
        self.assertEqual(s,original)
        return r

    def test_direct_salt_rankine_and_separate_ledgers(self):
        r=self.solve(case());row=r['steps'][0];c=row['rankine'];tower=row['tower']
        self.assertGreater(c['salt_input_mwth'],.09)
        self.assertEqual(c['oil_input_mwth'],0)
        self.assertNotIn('high_temp',row)
        self.assertEqual(row['devices']['3']['model_profile'],backend.TOWER_PROFILE)
        self.assertAlmostEqual(c['salt_input_mwth']*.97,c['steam_heat_mwth'],delta=EPS)
        self.assertAlmostEqual(tower['rankine_salt_input_mwth'],c['salt_input_mwth'],delta=EPS)
        for ledger,key in [(tower,'balance_error_mwth'),(tower,'energy_balance_error_mwhth'),(c,'balance_error_mw'),(row,'balance_error_mw')]:
            self.assertAlmostEqual(ledger[key],0,delta=EPS)
        self.assertAlmostEqual(r['totals']['rankine']['salt_input_mwhth'],c['salt_input_mwth'],delta=EPS)

    def test_day_charge_night_discharge(self):
        s=case(generation=.02,demand=0)
        night=copy.deepcopy(s['steps'][0]);night.update(time_s=3600,demand_mw={'7':1})
        night['weather'].update(is_day=False,solar_altitude_deg=-10)
        s['steps'].append(night)
        r=self.solve(s);day,night=r['steps']
        self.assertGreater(day['tower']['charge_mwth'],.09)
        self.assertAlmostEqual(day['tower']['discharge_mwth'],0,delta=EPS)
        self.assertGreater(night['rankine']['gross_electric_mw'],.01)
        self.assertAlmostEqual(night['tower']['useful_mwth'],0,delta=EPS)
        self.assertGreater(night['tower']['store_auxiliary_electric_mw'],0)
        for row in r['steps']:
            d=row['devices']['8'];self.assertLessEqual(min(d['charge_mwth'],d['discharge_mwth']),EPS)
            self.assertAlmostEqual(d['energy_mwhth'],d['energy_before_mwhth']*math.exp(-.005)+d['charge_mwth']*.98-d['discharge_mwth']/.98,delta=EPS)

    def test_empty_full_no_electric_and_disconnected_store(self):
        for s in [case(initial=0,night=True),case(initial=.5,night=True,generation=0),case(generation=0)]:
            row=self.solve(s)['steps'][0]
            self.assertAlmostEqual(row['rankine']['gross_electric_mw'],0,delta=EPS)
            self.assertAlmostEqual(row['tower']['charge_mwth'],0,delta=EPS)
            self.assertAlmostEqual(row['tower']['discharge_mwth'],0,delta=EPS)
        s=case(initial=.5,night=True);row=self.solve(s)['steps'][0]
        self.assertGreater(row['rankine']['gross_electric_mw'],0)
        s['links']=[l for l in s['links'] if not(l['from']==1 and l['to']==8)]
        self.assertAlmostEqual(self.solve(s)['steps'][0]['rankine']['gross_electric_mw'],0,delta=EPS)

    def test_full_headroom_zero_time_and_no_free_heat_sink(self):
        s=case(initial=.5,demand=0);s['options']['terminal_heat_soc_fraction']=1
        row=self.solve(s)['steps'][0]
        self.assertLess(row['tower']['charge_mwth'],.003)
        self.assertGreater(row['tower']['curtailed_mwth'],.68)
        row=self.solve(case(initial=.5,dt=0))['steps'][0]
        self.assertEqual(row['tower']['energy_mwhth'],.5)
        self.assertEqual(row['rankine']['gross_electric_mw'],0)

    def test_independent_audit_rejects_forged_ledgers_and_storage(self):
        s=case(initial=.5,night=True);p=backend.normalize(s);r=self.solve(s)
        for section,field in [('tower','balance_error_mwth'),('rankine','salt_input_mwth')]:
            rows=copy.deepcopy(r['steps']);rows[0][section][field]+=.01
            self.assertFalse(backend.validate_schedule(p,rows)['valid'])
        rows=copy.deepcopy(r['steps']);rows[0]['devices']['8']['auxiliary_electric_mw']=0
        self.assertFalse(backend.validate_schedule(p,rows)['valid'])

    def test_mixed_oil_salt_and_water_ledgers_remain_separate(self):
        from test_rankine_optimizer import case as old_case
        s=case();old=old_case(generation=.02)
        for d in old['devices']:
            d['id']+=20
        for line in old['links']:
            line['from']+=20;line['to']+=20
        s['devices']+=old['devices'];s['links']+=old['links']
        s['steps'][0]['available_mw']['20']=.02;s['steps'][0]['demand_mw']['27']=1
        row=self.solve(s)['steps'][0]
        self.assertGreater(row['rankine']['oil_input_mwth'],0)
        self.assertGreater(row['rankine']['salt_input_mwth'],0)
        self.assertAlmostEqual(row['high_temp']['rankine_oil_input_mwth'],row['rankine']['oil_input_mwth'],delta=EPS)
        self.assertAlmostEqual(row['tower']['rankine_salt_input_mwth'],row['rankine']['salt_input_mwth'],delta=EPS)
        self.assertAlmostEqual(row['thermal']['served_mwth'],0,delta=EPS)

    def test_bad_lp_storage_aux_and_source_bound_fail_independent_audit(self):
        original=backend.build_model
        def corrupt_aux(p):
            m=original(p)
            for terms,rel,rhs in m.rows:
                if 'h_discharge_0_8' in terms and any(k.startswith('x_') for k in terms):
                    terms['h_discharge_0_8']*=.5
            return m
        with mock.patch.object(backend,'build_model',side_effect=corrupt_aux):
            r=backend.solve(case(initial=.5,night=True),glpsol=GLPK)
        self.assertFalse(r['success']);self.assertTrue(r['solver_invoked'])
        def corrupt_source(p):
            m=original(p);m.bounds['solar_0_2']=(0,10)
            return m
        s=case();s['steps'][0]['weather']['dni_wm2']=10
        with mock.patch.object(backend,'build_model',side_effect=corrupt_source):
            r=backend.solve(s,glpsol=GLPK)
        self.assertFalse(r['success']);self.assertTrue(r['solver_invoked'])

    def test_salt_store_charge_requires_connected_external_ac(self):
        s=case(demand=0);s['options']['terminal_heat_soc_fraction']=.2
        r=self.solve(s)
        self.assertGreater(r['steps'][0]['tower']['charge_mwth'],0)
        s['links']=[l for l in s['links'] if not(l['from']==1 and l['to']==8)]
        r=backend.solve(s,glpsol=GLPK)
        self.assertFalse(r['success']);self.assertEqual(r['status'],'infeasible')

    def test_every_auxiliary_disconnect_and_hot_condenser_blocks_cycle(self):
        for sink in [2,3,5,6]:
            s=case();s['links']=[l for l in s['links'] if not(l['from']==1 and l['to']==sink)]
            with self.subTest(sink=sink):
                self.assertAlmostEqual(self.solve(s)['steps'][0]['rankine']['gross_electric_mw'],0,delta=EPS)
        s=case();s['steps'][0]['weather']['air_temp_c']=36
        self.assertAlmostEqual(self.solve(s)['steps'][0]['rankine']['gross_electric_mw'],0,delta=EPS)

    def test_old_rankine_result_keeps_original_schema_and_keys(self):
        from test_rankine_optimizer import case as old_case
        r=self.solve(old_case())
        self.assertEqual(r['schema_version'],5)
        self.assertNotIn('tower',r['steps'][0])
        self.assertNotIn('salt_input_mwth',r['steps'][0]['rankine'])
        self.assertNotIn('salt_input_mwhth',r['totals']['rankine'])


if __name__=='__main__':unittest.main()
