"""V19 DNI/oil-grade chain, real GLPK coupling and adversarial audits."""
import copy
import math
import unittest
from unittest import mock
from test_thermal_dispatch_solver import backend, GLPK, EPS, device as old_device, cable, heat_line

def device(ident, kind, params=None):
    d = old_device(ident, kind, params)
    if kind in backend.HIGH_TEMP_KINDS:
        d["model_profile"] = backend.HIGH_TEMP_PROFILE
    return d


def edge(a, b, ak, bk, cap=1):
    line = heat_line(a, b, ak, bk, cap)
    line['carrier'] = 'heat_oil' if line['grade_id'] == backend.OIL_GRADE else 'heat_water'
    return line


def case(dni=800, generation=1, demand=1, dt=1):
    return {'schema_version': 4,
            'devices': [device(0, 'wind'), device(1, 'station', {'capacity_mw': 10, 'loss_fraction': 0}),
                        device(2, 'parabolic_trough'), device(3, 'oil_water_exchanger'),
                        device(4, 'heat_exchanger'), device(5, 'heat_demand')],
            'links': [cable(0, 1), cable(1, 2, boiler=True), cable(1, 3, boiler=True),
                      edge(2, 3, 'parabolic_trough', 'oil_water_exchanger'),
                      edge(3, 4, 'oil_water_exchanger', 'heat_exchanger'),
                      edge(4, 5, 'heat_exchanger', 'heat_demand')],
            'steps': [{'time_s': 0, 'dt_h': dt, 'available_mw': {'0': generation}, 'demand_mw': {},
                       'heat_demand_mwth': {'5': demand}, 'weather': {'dni_wm2': dni, 'air_temp_c': 20,
                       'solar_altitude_deg': 90, 'solar_azimuth_deg': 180}}], 'options': {'timeout_s': 30}}


def store(s, initial=0):
    d = device(6, 'high_temp_store', {'self_discharge_per_h': 0})
    d['state'] = {'energy_mwhth': initial}
    s['devices'].append(d)
    s['links'] += [edge(2, 6, 'parabolic_trough', 'high_temp_store'), edge(6, 3, 'high_temp_store', 'oil_water_exchanger')]
    return s


class TroughInputs(unittest.TestCase):
    def test_aperture_dni_and_single_axis_cosine(self):
        w = case()['steps'][0]['weather']; p = backend.DEFAULTS['parabolic_trough']
        r = backend.trough_physics(p, w)
        self.assertAlmostEqual(r['available_mwth'], .0392189208)
        w.update(solar_altitude_deg=30, solar_azimuth_deg=180)
        r = backend.trough_physics(p, w)
        self.assertAlmostEqual(r['cos_incidence'], .5)
        self.assertAlmostEqual(r['available_mwth'], 69.24*(.75*800*.5-.1*230-.0002*230**2)/1e6)
        self.assertAlmostEqual(r['incident_mw'], r['optical_rejection_mw']+r['thermal_loss_mw']+r['available_mwth'])

    def test_missing_invalid_dni_never_uses_poa(self):
        for field, value in [('dni_wm2', None), ('dni_wm2', -1), ('dni_wm2', float('nan')),
                             ('dni_wm2', True), ('air_temp_c', None), ('solar_altitude_deg', None),
                             ('solar_azimuth_deg', None), ('solar_altitude_deg', 91), ('is_day', 1)]:
            s = case(); s['steps'][0]['weather'][field] = value
            s['steps'][0]['weather']['irradiance_wm2'] = 1000
            with self.subTest(field=field, value=value), self.assertRaises(backend.InputError): backend.normalize(s)

    def test_typed_routes_strict_and_no_upgrading(self):
        edits = [lambda s: s.update(schema_version=3),
                 lambda s: s['links'][3].update(carrier='heat_water'),
                 lambda s: s['links'][3].update(grade_id=backend.PRIMARY_GRADE),
                 lambda s: s['links'][3].update(to=4),
                 lambda s: s['links'][4].update(to=5),
                 lambda s: s['links'][4].update(to=2),
                 lambda s: s['devices'][2]['params'].update(supply_temp_c=301),
                 lambda s: s['devices'][3]['params'].update(min_approach_k=141),
                 lambda s: s['devices'][3]['params'].update(auxiliary_electric_ratio=0),
                 lambda s: s['steps'][0].update(trough_available_mwth={'2': 3})]
        for edit in edits:
            s=case(); edit(s)
            with self.subTest(edit=edit), self.assertRaises(backend.InputError): backend.normalize(s)


@unittest.skipUnless(GLPK, 'Requires real GLPK')
class TroughOptimizer(unittest.TestCase):
    def solve(self, s):
        original=copy.deepcopy(s); r=backend.solve(s, glpsol=GLPK)
        self.assertTrue(r['success'], r)
        self.assertTrue(r['validation']['valid'], r)
        self.assertTrue(r['solver_invoked']); self.assertEqual(s, original)
        return r

    def test_sunny_chain_and_separate_carriers(self):
        r=self.solve(case()); row=r['steps'][0]; h=row['high_temp']; q=.0392189208
        self.assertEqual(r['schema_version'], 4)
        self.assertNotIn('solar', row)
        self.assertAlmostEqual(h['useful_mwth'], q, delta=EPS)
        self.assertAlmostEqual(h['collector_auxiliary_electric_mw'], .02*q, delta=EPS)
        self.assertAlmostEqual(h['oil_auxiliary_electric_mw'], .01*q, delta=EPS)
        self.assertAlmostEqual(h['auxiliary_electric_mw'], .03*q, delta=EPS)
        self.assertAlmostEqual(h['oil_water_output_mwth'], .98*q, delta=EPS)
        self.assertAlmostEqual(row['thermal']['served_mwth'], .98**2*q, delta=EPS)
        self.assertAlmostEqual(h['balance_error_mwth'], 0, delta=EPS)
        self.assertAlmostEqual(row['balance_error_mw'], 0, delta=EPS)
        self.assertAlmostEqual(r['totals']['high_temp']['useful_mwhth'], q, delta=EPS)

    def test_night_paused_no_sink_and_no_electricity(self):
        for mode in ['night', 'altitude', 'low_dni', 'paused', 'no_power', 'no_trough_aux', 'no_oil_aux', 'no_sink']:
            s=case()
            if mode=='night': s['steps'][0]['weather']['is_day']=False
            if mode=='altitude': s['steps'][0]['weather']['solar_altitude_deg']=0
            if mode=='low_dni': s['steps'][0]['weather']['dni_wm2']=1
            if mode=='paused': s['steps'][0]['dt_h']=0
            if mode=='no_power': s['steps'][0]['available_mw']['0']=0
            if mode=='no_trough_aux': s['links'].pop(1)
            if mode=='no_oil_aux': s['links'].pop(2)
            if mode=='no_sink': s['steps'][0]['heat_demand_mwth']['5']=0
            with self.subTest(mode=mode):
                row=self.solve(s)['steps'][0]
                self.assertAlmostEqual(row['high_temp']['useful_mwth'], 0, delta=EPS)
                self.assertAlmostEqual(row['thermal']['served_mwth'], 0, delta=EPS)

    def test_each_bottleneck_bounds_useful_source(self):
        for mode in ['oil_edge','water_edge','oil_hx','water_hx','trough_ac','oil_ac','source','station','demand']:
            s=case(); q=.01
            if mode=='oil_edge': s['links'][3]['capacity_mwth']=q
            if mode=='water_edge': s['links'][4]['capacity_mwth']=q*.98
            if mode=='oil_hx': s['devices'][3]['params']['capacity_mwth']=q
            if mode=='water_hx': s['devices'][4]['params']['capacity_mwth']=q*.98
            if mode=='trough_ac': s['links'][1]['capacity_mw']=q*.02
            if mode=='oil_ac': s['links'][2]['capacity_mw']=q*.01
            if mode=='source': s['steps'][0]['available_mw']['0']=q*.03
            if mode=='station': s['devices'][1]['params']['capacity_mw']=q*.03
            if mode=='demand': s['steps'][0]['heat_demand_mwth']['5']=q*.98**2
            with self.subTest(mode=mode):
                row=self.solve(s)['steps'][0]
                self.assertAlmostEqual(row['high_temp']['useful_mwth'], q, delta=EPS)

    def test_sunny_charge_night_discharge_and_water_inventory_separate(self):
        s=store(case(demand=0)); second=copy.deepcopy(s['steps'][0])
        second.update(time_s=3600, heat_demand_mwth={'5':1}); second['weather']['is_day']=False
        s['steps'].append(second); r=self.solve(s)
        self.assertGreater(r['steps'][0]['high_temp']['energy_mwhth'], 0)
        self.assertEqual(r['steps'][0]['thermal']['energy_mwhth'], 0)
        self.assertAlmostEqual(r['steps'][1]['thermal']['served_mwth'], .0392189208*.98**4, delta=EPS)
        self.assertAlmostEqual(r['steps'][1]['devices']['3']['auxiliary_electric_mw'], .0392189208*.98**2*.01, delta=EPS)
        self.assertAlmostEqual(r['steps'][1]['high_temp']['energy_mwhth'], 0, delta=EPS)
        self.assertEqual(set(r['final_states']['6']), {'energy_mwhth'})

    def test_initial_inventory_cannot_discharge_without_oil_auxiliary(self):
        s=store(case(dni=0), initial=.1); s['links'].pop(2)
        row=self.solve(s)['steps'][0]
        self.assertAlmostEqual(row['high_temp']['energy_mwhth'], .1, delta=EPS)
        self.assertAlmostEqual(row['thermal']['served_mwth'], 0, delta=EPS)

    def test_full_store_and_zero_demand_does_not_dump_heat(self):
        row=self.solve(store(case(demand=0), initial=.2))['steps'][0]
        self.assertAlmostEqual(row['high_temp']['useful_mwth'], 0, delta=EPS)
        self.assertAlmostEqual(row['high_temp']['energy_mwhth'], .2, delta=EPS)

    def test_report_tampering_rejected_independently(self):
        s=store(case()); p=backend.normalize(s); r=self.solve(s)
        edits=[lambda row: row['devices']['2'].update(available_mwth=1),
               lambda row: row['devices']['2'].update(cos_incidence=.2),
               lambda row: row['devices']['3'].update(auxiliary_electric_mw=0),
               lambda row: row['devices']['3'].update(hot_return_c=60),
               lambda row: row['high_temp'].update(useful_mwth=1),
               lambda row: row['high_temp'].update(oil_auxiliary_electric_mw=0),
               lambda row: row['thermal'].update(balance_error_mwth=1),
               lambda row: row['devices']['6'].update(energy_mwhth=.2),
               lambda row: row['lines'][3].update(carrier='heat_water')]
        for edit in edits:
            reports=copy.deepcopy(r['steps']); edit(reports[0])
            with self.subTest(edit=edit): self.assertFalse(backend.validate_schedule(p,reports)['valid'])

    def test_mixed_poa_dni_sources_and_water_inventory(self):
        s=store(case())
        s['devices'] += [device(7, 'solar_thermal'), device(8, 'thermal_store')]
        s['links'] += [cable(1,7,boiler=True), edge(7,4,'solar_thermal','heat_exchanger'),
                       edge(7,8,'solar_thermal','thermal_store'), edge(8,4,'thermal_store','heat_exchanger')]
        s['steps'][0]['weather'].update(irradiance_wm2=1000, irradiance_kind='poa')
        row=self.solve(s)['steps'][0]
        self.assertAlmostEqual(row['high_temp']['useful_mwth'], .0392189208, delta=EPS)
        q=30.3*(785-1.42*55-.005*55**2)/1e6
        self.assertAlmostEqual(row['solar']['useful_mwth'], q, delta=EPS)
        self.assertAlmostEqual(row['thermal']['served_mwth'], .0392189208*.98**2+q*.98, delta=EPS)

    def test_store_decay_terminal_floor_and_paused_inventory(self):
        s=store(case(dni=0),initial=.1); s['devices'][6]['params']['self_discharge_per_h']=.005
        s['options']['terminal_heat_soc_fraction']=.25
        row=self.solve(s)['steps'][0]
        expected_discharge=(.1*math.exp(-.005)-.05)*.98
        self.assertAlmostEqual(row['high_temp']['energy_mwhth'],.05,delta=EPS)
        self.assertAlmostEqual(row['high_temp']['discharge_mwth'],expected_discharge,delta=EPS)
        self.assertAlmostEqual(row['high_temp']['self_discharge_mwhth'],.1*(1-math.exp(-.005)),delta=EPS)
        s['steps'][0]['dt_h']=0
        row=self.solve(s)['steps'][0]
        self.assertAlmostEqual(row['high_temp']['energy_mwhth'],.1,delta=EPS)
        self.assertEqual(row['high_temp']['self_discharge_mwhth'],0)

    def test_old_v18_reports_bytewise_frozen(self):
        # Hashes were generated with the untouched pre-V19 backend and real GLPK.
        # Runtime/temporary-path solver logs are deliberately outside the contract.
        import hashlib
        import json
        from test_dispatch_solver import basic_snapshot
        from test_thermal_dispatch_solver import direct, with_store
        from test_fuel_optimizer import fuel_case
        from test_solar_optimizer import solar_case
        fixtures=[(basic_snapshot,'4bdf89bbb0de8990233219c1a339a29c6eecbb2902b684a3a2ed7266d5287309'),
                  (direct,'ecc99e45b04c21700306e2d139985e955d6187ebad9cecd64de76d6c65fcf5c5'),
                  (with_store,'85000bc61efcfedbf46637626390e2f315cbbc0ba8322beb659894e958f2a172'),
                  (fuel_case,'b1a24e9317ed68a3eaee06a952bbf6b602564961586911503b1b5738cfddcc42'),
                  (solar_case,'a78bd8ac51df00c1a9dfcb7311ed02b182bc9adc5b22580e8597c999f5b92698')]
        for fixture, expected in fixtures:
            result=self.solve(fixture()); result.pop('elapsed_s'); result.pop('solver_stages')
            encoded=json.dumps(result,separators=(',',':'),ensure_ascii=False).encode()
            with self.subTest(fixture=fixture.__name__): self.assertEqual(hashlib.sha256(encoded).hexdigest(),expected)

    def test_corrupt_weather_cache_model_is_caught_by_physics(self):
        s=case(); original=backend.build_model
        def corrupt(problem):
            problem['steps'][0]['solar_available_mwth']['2']=10
            return original(problem)
        with mock.patch.object(backend,'build_model',side_effect=corrupt):
            r=backend.solve(s,glpsol=GLPK)
        self.assertFalse(r['success']); self.assertTrue(r['solver_invoked'])

if __name__=='__main__': unittest.main()
