--!strict
-- HighwayScenery: where the highway's biome scenery stands (pens3 phase 12b, 2026-10-18; the owner: "the biomes have
-- to be themed too"): the decor rows of the lobby design v6's layout.json (`L:n` = its line n), copied 1:1 for SDTools
-- HighwayBuilder, which builds each row's piece in its biome's Model. Edit time only (ServerStorage.SDTools); data, no
-- requires. The rows are written by work/pens3/p12b/tools/gen_scenery.py from layout.json, each with its line.
-- A row is v6's own entry: `id` (the piece's name, its kind before the last "_NN"), `at` (v6's world point: x, y, and
-- z = -62 - d, L:1), `rot` (v6's yaw in degrees, the sign of Roblox Orientation.Y, L:1) and, on gumdrop trees and
-- popsicles, `tint` (the Palette token of the row's L GumdropTint / PopsicleTint). The kinds: gumdrop_tree,
-- lollipop_lamp, candy_hill (Candy Meadow reuses the lobby's, HK:30), bt_bread_house, bt_croissant_hill, bl_cup_island,
-- fd_popsicle, fd_sundae_peak, lv_basalt_rock, lv_volcano, rr_cloud_bank, rr_planet, dh_gold_cloud and
-- dh_marble_pillar; the clouds under the sky arches (L:1131-1132, :1398-1399) and the Golden Gates (L:1598-1599) are
-- rows too. The same layout's boosters, traps and reward bubbles are gameplay (phases 15 and 17), not here.

export type Row = { id: string, at: Vector3, rot: number, tint: string? }

-- row(id, x, y, z, rot, tint?): one v6 entry.
local function row(id: string, x: number, y: number, z: number, rot: number, tint: string?): Row
	return { id = id, at = Vector3.new(x, y, z), rot = rot, tint = tint }
end

local HighwayScenery = {
	v6Zero = 62, -- L:1 "z = -62 - d": a v6 point (x, y, z) is the lane-local point (x, y, z + 62)
	-- L:1597 dh_golden_gates_01 at z -8,412: v6's gates stand at d 8,350, ours at Config.Economy.Highway.gatesAt
	-- (PR3:36). Only the clouds under them ("role": "gate support") move with them; every other row keeps its v6
	-- distance beside the lane, which ends at 8,500 in v6 too (L:1369).
	v6GatesAt = 8350,
	gateSupports = { dh_gold_cloud_41 = true, dh_gold_cloud_42 = true } :: { [string]: boolean }, -- L:1598-1599
	biomes = {
		{ -- 1 Candy Meadow (Biome_1_CM): 10 rows
			row("lollipop_lamp_35", -19, 0, -212, 180), -- L:488
			row("lollipop_lamp_36", -19, 0, -262, 180), -- L:489
			row("lollipop_lamp_37", -19, 0, -312, 180), -- L:490
			row("gumdrop_tree_17", -26, 0, -222, -28.5, "HighwayPinkIcing"), -- L:491
			row("gumdrop_tree_18", 35.875, 0, -250, 75.8, "HighwayLemon"), -- L:492
			row("gumdrop_tree_19", -50.75, 0, -278, -168.2, "HighwayLilac"), -- L:493
			row("gumdrop_tree_20", 37.25, 0, -306, -89.3, "HighwayAqua"), -- L:494
			row("gumdrop_tree_21", -51.625, 0, -334, -164.6, "HighwayPinkIcing"), -- L:495
			row("candy_hill_22", -114.25, 0, -252, -131.1), -- L:496
			row("candy_hill_23", 120.875, 0, -307, 87.1), -- L:497
		},
		{ -- 2 Bakery Town (Biome_2_BT): 16 rows
			row("bt_bread_house_01", -40.75, 0, -382, 90), -- L:551
			row("bt_bread_house_02", 46.75, 0, -427, -90), -- L:552
			row("bt_bread_house_03", -46.625, 0, -472, 90), -- L:553
			row("bt_bread_house_04", 35, 0, -517, -90), -- L:554
			row("bt_bread_house_05", -46.25, 0, -562, 90), -- L:555
			row("bt_bread_house_06", 42.375, 0, -607, -90), -- L:556
			row("bt_bread_house_07", -50.625, 0, -652, 90), -- L:557
			row("bt_bread_house_08", 48.5, 0, -697, -90), -- L:558
			row("bt_bread_house_09", -36.25, 0, -742, 90), -- L:559
			row("bt_bread_house_10", 43.25, 0, -787, -90), -- L:560
			row("bt_bread_house_11", -50.625, 0, -832, 90), -- L:561
			row("bt_croissant_hill_01", -144.375, 0, -412, -128.2), -- L:562
			row("bt_croissant_hill_02", 138.875, 0, -502, -31.7), -- L:563
			row("bt_croissant_hill_03", -155.375, 0, -592, 134), -- L:564
			row("bt_croissant_hill_04", 126.75, 0, -682, -58.6), -- L:565
			row("bt_croissant_hill_05", -126.625, 0, -772, 54.9), -- L:566
		},
		{ -- 3 Boba Lagoon (Biome_3_BL): 10 rows
			row("bl_cup_island_01", -59.875, -2, -892, 154.2), -- L:643
			row("bl_cup_island_02", 59.75, -2, -962, -22.6), -- L:644
			row("bl_cup_island_03", -70.25, -2, -1032, -97.5), -- L:645
			row("bl_cup_island_04", 83.125, -2, -1102, 21.1), -- L:646
			row("bl_cup_island_05", -59, -2, -1172, -158.2), -- L:647
			row("bl_cup_island_06", 68.375, -2, -1242, 151.7), -- L:648
			row("bl_cup_island_07", -55.75, -2, -1312, -32.8), -- L:649
			row("bl_cup_island_08", 50.25, -2, -1382, 131.6), -- L:650
			row("bl_cup_island_09", -61.75, -2, -1452, -120.8), -- L:651
			row("bl_cup_island_10", 85, -2, -1522, -174.7), -- L:652
		},
		{ -- 4 Frozen Dessert Peaks (Biome_4_FD): 29 rows
			row("fd_popsicle_01", -24, 0, -1587, -3.8, "HighwayPinkIcing"), -- L:761
			row("fd_popsicle_02", 24.75, 0, -1637, -5.4, "HighwayBiome4"), -- L:762
			row("fd_popsicle_03", -25.5, 0, -1687, -6.7, "HighwayCoatJelly"), -- L:763
			row("fd_popsicle_04", 26.25, 0, -1737, 4.6, "HighwayLemon"), -- L:764
			row("fd_popsicle_05", -24.375, 0, -1787, 16.3, "HighwayPinkIcing"), -- L:765
			row("fd_popsicle_06", 25.75, 0, -1837, 14.5, "HighwayBiome4"), -- L:766
			row("fd_popsicle_07", -26.75, 0, -1887, 5.4, "HighwayCoatJelly"), -- L:767
			row("fd_popsicle_08", 26.125, 0, -1937, 0.2, "HighwayLemon"), -- L:768
			row("fd_popsicle_09", -27.125, 0, -1987, 17.6, "HighwayPinkIcing"), -- L:769
			row("fd_popsicle_10", 25.375, 0, -2037, 8.3, "HighwayBiome4"), -- L:770
			row("fd_popsicle_11", -24.5, 0, -2087, 3.5, "HighwayCoatJelly"), -- L:771
			row("fd_popsicle_12", 25.125, 0, -2137, -6.8, "HighwayLemon"), -- L:772
			row("fd_popsicle_13", -25.375, 0, -2187, 11.8, "HighwayPinkIcing"), -- L:773
			row("fd_popsicle_14", 28.25, 0, -2237, -15.6, "HighwayBiome4"), -- L:774
			row("fd_popsicle_15", -27.875, 0, -2287, -16.9, "HighwayCoatJelly"), -- L:775
			row("fd_popsicle_16", 25.5, 0, -2337, -13.9, "HighwayLemon"), -- L:776
			row("fd_popsicle_17", -23.5, 0, -2387, 19.8, "HighwayPinkIcing"), -- L:777
			row("fd_popsicle_18", 24.375, 0, -2437, 5.3, "HighwayBiome4"), -- L:778
			row("fd_popsicle_19", -23.875, 0, -2487, -1.7, "HighwayCoatJelly"), -- L:779
			row("fd_popsicle_20", 26.5, 0, -2537, -14.5, "HighwayLemon"), -- L:780
			row("fd_sundae_peak_01", -150.25, 0, -1622, -41.6), -- L:781
			row("fd_sundae_peak_02", 148.375, 0, -1732, -41.3), -- L:782
			row("fd_sundae_peak_03", -149.5, 0, -1842, -86), -- L:783
			row("fd_sundae_peak_04", 111.5, 0, -1952, 3.8), -- L:784
			row("fd_sundae_peak_05", -109.875, 0, -2062, 27.4), -- L:785
			row("fd_sundae_peak_06", 95.125, 0, -2172, -137.9), -- L:786
			row("fd_sundae_peak_07", -108.875, 0, -2282, -93.2), -- L:787
			row("fd_sundae_peak_08", 124.375, 0, -2392, -112.5), -- L:788
			row("fd_sundae_peak_09", -109.25, 0, -2502, -42.4), -- L:789
		},
		{ -- 5 Lava Volcano (Biome_5_LV): 39 rows
			row("lv_basalt_rock_01", -26.75, 0, -2577, 134.6), -- L:951
			row("lv_basalt_rock_02", 39.875, 0, -2617, 42.6), -- L:952
			row("lv_basalt_rock_03", -31.75, 0, -2657, 1.1), -- L:953
			row("lv_basalt_rock_04", 40.25, 0, -2697, -130.7), -- L:954
			row("lv_basalt_rock_05", -40.5, 0, -2737, 7.6), -- L:955
			row("lv_basalt_rock_06", 40, 0, -2777, 67.7), -- L:956
			row("lv_basalt_rock_07", -41.375, 0, -2817, -156.5), -- L:957
			row("lv_basalt_rock_08", 35.625, 0, -2857, 95.9), -- L:958
			row("lv_basalt_rock_09", -26.5, 0, -2897, 75.2), -- L:959
			row("lv_basalt_rock_10", 33.25, 0, -2937, 18.8), -- L:960
			row("lv_basalt_rock_11", -37.375, 0, -2977, -107.7), -- L:961
			row("lv_basalt_rock_12", 36.25, 0, -3017, 179.3), -- L:962
			row("lv_basalt_rock_13", -22.625, 0, -3057, 39.7), -- L:963
			row("lv_basalt_rock_14", 40.375, 0, -3097, 47.1), -- L:964
			row("lv_basalt_rock_15", -35.75, 0, -3137, -38.5), -- L:965
			row("lv_basalt_rock_16", 22.75, 0, -3177, -42.1), -- L:966
			row("lv_basalt_rock_17", -39.25, 0, -3217, -2.6), -- L:967
			row("lv_basalt_rock_18", 41.125, 0, -3257, -84.6), -- L:968
			row("lv_basalt_rock_19", -30.375, 0, -3297, 89.4), -- L:969
			row("lv_basalt_rock_20", 36.5, 0, -3337, -42.4), -- L:970
			row("lv_basalt_rock_21", -30, 0, -3377, 84.5), -- L:971
			row("lv_basalt_rock_22", 30.125, 0, -3417, -40.7), -- L:972
			row("lv_basalt_rock_23", -33.125, 0, -3457, 126.5), -- L:973
			row("lv_basalt_rock_24", 34.375, 0, -3497, -95.4), -- L:974
			row("lv_basalt_rock_25", -28.75, 0, -3537, -98.9), -- L:975
			row("lv_basalt_rock_26", 30.5, 0, -3577, 71.5), -- L:976
			row("lv_basalt_rock_27", -28.25, 0, -3617, -5.2), -- L:977
			row("lv_basalt_rock_28", 41.875, 0, -3657, -132.3), -- L:978
			row("lv_basalt_rock_29", -39.5, 0, -3697, -29.4), -- L:979
			row("lv_basalt_rock_30", 26, 0, -3737, -127.7), -- L:980
			row("lv_basalt_rock_31", -24.75, 0, -3777, 179.1), -- L:981
			row("lv_basalt_rock_32", 33.125, 0, -3817, -82.3), -- L:982
			row("lv_basalt_rock_33", -40.875, 0, -3857, 173.5), -- L:983
			row("lv_basalt_rock_34", 25.75, 0, -3897, 160.8), -- L:984
			row("lv_basalt_rock_35", -25.375, 0, -3937, -121.5), -- L:985
			row("lv_basalt_rock_36", 32.375, 0, -3977, -157.9), -- L:986
			row("lv_basalt_rock_37", -32.125, 0, -4017, -87.4), -- L:987
			row("lv_basalt_rock_38", 29.25, 0, -4057, -89.7), -- L:988
			row("lv_volcano_01", -230, 0, -3312, 0), -- L:989
		},
		{ -- 6 Rainbow Road (Biome_6_RR): 38 rows
			row("rr_cloud_bank_01", -26.125, -9, -4062, 0), -- L:1131
			row("rr_cloud_bank_02", 26.125, -9, -4062, 0), -- L:1132
			row("rr_cloud_bank_03", -41.875, -24.621, -4092, -165), -- L:1186
			row("rr_cloud_bank_04", 54.25, -16.987, -4152, 104.7), -- L:1187
			row("rr_cloud_bank_05", -56.5, -18.128, -4212, 154.5), -- L:1188
			row("rr_cloud_bank_06", 45.25, -16.088, -4272, -63.8), -- L:1189
			row("rr_cloud_bank_07", -104.125, -13.62, -4332, -114.9), -- L:1190
			row("rr_cloud_bank_08", 107.125, -29.546, -4392, -85.7), -- L:1191
			row("rr_cloud_bank_09", -82.125, -16.967, -4452, -36.6), -- L:1192
			row("rr_cloud_bank_10", 42.625, -27.553, -4512, 28.9), -- L:1193
			row("rr_cloud_bank_11", -47.625, -28.473, -4572, 3.4), -- L:1194
			row("rr_cloud_bank_12", 82.375, -12.977, -4632, 69.1), -- L:1195
			row("rr_cloud_bank_13", -49.375, -26.36, -4692, -117), -- L:1196
			row("rr_cloud_bank_14", 57, -21.786, -4752, -2.2), -- L:1197
			row("rr_cloud_bank_15", -69.625, -17.872, -4812, -81.2), -- L:1198
			row("rr_cloud_bank_16", 67.75, -22.504, -4872, 22), -- L:1199
			row("rr_cloud_bank_17", -56.125, -15.463, -4932, -9.2), -- L:1200
			row("rr_cloud_bank_18", 50.625, -13.34, -4992, -176.9), -- L:1201
			row("rr_cloud_bank_19", -48.5, -26.218, -5052, -143.1), -- L:1202
			row("rr_cloud_bank_20", 51.875, -28.595, -5112, 98.2), -- L:1203
			row("rr_cloud_bank_21", -85.25, -19.99, -5172, 173), -- L:1204
			row("rr_cloud_bank_22", 109.625, -28.646, -5232, 148.8), -- L:1205
			row("rr_cloud_bank_23", -62, -29.925, -5292, 2.2), -- L:1206
			row("rr_cloud_bank_24", 69, -28.356, -5352, 84.3), -- L:1207
			row("rr_cloud_bank_25", -104.625, -16.006, -5412, -85), -- L:1208
			row("rr_cloud_bank_26", 70.625, -14.611, -5472, -13.5), -- L:1209
			row("rr_cloud_bank_27", -96.125, -18.087, -5532, -154), -- L:1210
			row("rr_cloud_bank_28", 64.375, -22.674, -5592, 178.9), -- L:1211
			row("rr_cloud_bank_29", -74.625, -19.786, -5652, -100.2), -- L:1212
			row("rr_cloud_bank_30", 86.5, -18.609, -5712, -97.6), -- L:1213
			row("rr_cloud_bank_31", -101.875, -14.787, -5772, -4.2), -- L:1214
			row("rr_cloud_bank_32", 70.625, -21.233, -5832, -15.4), -- L:1215
			row("rr_cloud_bank_33", -108.25, -23.56, -5892, 28.5), -- L:1216
			row("rr_cloud_bank_34", 64, -14.112, -5952, -105), -- L:1217
			row("rr_cloud_bank_35", -91.625, -12.807, -6012, -76.7), -- L:1218
			row("rr_planet_01", -260, 60, -4562, 74.5), -- L:1219
			row("rr_planet_02", 300, 110, -5262, 85.7), -- L:1220
			row("rr_planet_03", -320, 90, -5862, -72.5), -- L:1221
		},
		{ -- 7 Divine Heaven (Biome_7_DH): 134 rows
			row("dh_gold_cloud_01", -28.75, -9, -6062, 0), -- L:1398
			row("dh_gold_cloud_02", 28.75, -9, -6062, 0), -- L:1399
			row("dh_marble_pillar_01", -22, 1, -6087, 0), -- L:1467
			row("dh_marble_pillar_02", 22, 1, -6087, 0), -- L:1468
			row("dh_marble_pillar_03", -22, 1, -6137, 0), -- L:1469
			row("dh_marble_pillar_04", 22, 1, -6137, 0), -- L:1470
			row("dh_marble_pillar_05", -22, 1, -6187, 0), -- L:1471
			row("dh_marble_pillar_06", 22, 1, -6187, 0), -- L:1472
			row("dh_marble_pillar_07", -22, 1, -6237, 0), -- L:1473
			row("dh_marble_pillar_08", 22, 1, -6237, 0), -- L:1474
			row("dh_marble_pillar_09", -22, 1, -6287, 0), -- L:1475
			row("dh_marble_pillar_10", 22, 1, -6287, 0), -- L:1476
			row("dh_marble_pillar_11", -22, 1, -6337, 0), -- L:1477
			row("dh_marble_pillar_12", 22, 1, -6337, 0), -- L:1478
			row("dh_marble_pillar_13", -22, 1, -6387, 0), -- L:1479
			row("dh_marble_pillar_14", 22, 1, -6387, 0), -- L:1480
			row("dh_marble_pillar_15", -22, 1, -6437, 0), -- L:1481
			row("dh_marble_pillar_16", 22, 1, -6437, 0), -- L:1482
			row("dh_marble_pillar_17", -22, 1, -6487, 0), -- L:1483
			row("dh_marble_pillar_18", 22, 1, -6487, 0), -- L:1484
			row("dh_marble_pillar_19", -22, 1, -6537, 0), -- L:1485
			row("dh_marble_pillar_20", 22, 1, -6537, 0), -- L:1486
			row("dh_marble_pillar_21", -22, 1, -6587, 0), -- L:1487
			row("dh_marble_pillar_22", 22, 1, -6587, 0), -- L:1488
			row("dh_marble_pillar_23", -22, 1, -6637, 0), -- L:1489
			row("dh_marble_pillar_24", 22, 1, -6637, 0), -- L:1490
			row("dh_marble_pillar_25", -22, 1, -6687, 0), -- L:1491
			row("dh_marble_pillar_26", 22, 1, -6687, 0), -- L:1492
			row("dh_marble_pillar_27", -22, 1, -6737, 0), -- L:1493
			row("dh_marble_pillar_28", 22, 1, -6737, 0), -- L:1494
			row("dh_marble_pillar_29", -22, 1, -6787, 0), -- L:1495
			row("dh_marble_pillar_30", 22, 1, -6787, 0), -- L:1496
			row("dh_marble_pillar_31", -22, 1, -6837, 0), -- L:1497
			row("dh_marble_pillar_32", 22, 1, -6837, 0), -- L:1498
			row("dh_marble_pillar_33", -22, 1, -6887, 0), -- L:1499
			row("dh_marble_pillar_34", 22, 1, -6887, 0), -- L:1500
			row("dh_marble_pillar_35", -22, 1, -6937, 0), -- L:1501
			row("dh_marble_pillar_36", 22, 1, -6937, 0), -- L:1502
			row("dh_marble_pillar_37", -22, 1, -6987, 0), -- L:1503
			row("dh_marble_pillar_38", 22, 1, -6987, 0), -- L:1504
			row("dh_marble_pillar_39", -22, 1, -7037, 0), -- L:1505
			row("dh_marble_pillar_40", 22, 1, -7037, 0), -- L:1506
			row("dh_marble_pillar_41", -22, 1, -7087, 0), -- L:1507
			row("dh_marble_pillar_42", 22, 1, -7087, 0), -- L:1508
			row("dh_marble_pillar_43", -22, 1, -7137, 0), -- L:1509
			row("dh_marble_pillar_44", 22, 1, -7137, 0), -- L:1510
			row("dh_marble_pillar_45", -22, 1, -7187, 0), -- L:1511
			row("dh_marble_pillar_46", 22, 1, -7187, 0), -- L:1512
			row("dh_marble_pillar_47", -22, 1, -7237, 0), -- L:1513
			row("dh_marble_pillar_48", 22, 1, -7237, 0), -- L:1514
			row("dh_marble_pillar_49", -22, 1, -7287, 0), -- L:1515
			row("dh_marble_pillar_50", 22, 1, -7287, 0), -- L:1516
			row("dh_marble_pillar_51", -22, 1, -7337, 0), -- L:1517
			row("dh_marble_pillar_52", 22, 1, -7337, 0), -- L:1518
			row("dh_marble_pillar_53", -22, 1, -7387, 0), -- L:1519
			row("dh_marble_pillar_54", 22, 1, -7387, 0), -- L:1520
			row("dh_marble_pillar_55", -22, 1, -7437, 0), -- L:1521
			row("dh_marble_pillar_56", 22, 1, -7437, 0), -- L:1522
			row("dh_marble_pillar_57", -22, 1, -7487, 0), -- L:1523
			row("dh_marble_pillar_58", 22, 1, -7487, 0), -- L:1524
			row("dh_marble_pillar_59", -22, 1, -7537, 0), -- L:1525
			row("dh_marble_pillar_60", 22, 1, -7537, 0), -- L:1526
			row("dh_marble_pillar_61", -22, 1, -7587, 0), -- L:1527
			row("dh_marble_pillar_62", 22, 1, -7587, 0), -- L:1528
			row("dh_marble_pillar_63", -22, 1, -7637, 0), -- L:1529
			row("dh_marble_pillar_64", 22, 1, -7637, 0), -- L:1530
			row("dh_marble_pillar_65", -22, 1, -7687, 0), -- L:1531
			row("dh_marble_pillar_66", 22, 1, -7687, 0), -- L:1532
			row("dh_marble_pillar_67", -22, 1, -7737, 0), -- L:1533
			row("dh_marble_pillar_68", 22, 1, -7737, 0), -- L:1534
			row("dh_marble_pillar_69", -22, 1, -7787, 0), -- L:1535
			row("dh_marble_pillar_70", 22, 1, -7787, 0), -- L:1536
			row("dh_marble_pillar_71", -22, 1, -7837, 0), -- L:1537
			row("dh_marble_pillar_72", 22, 1, -7837, 0), -- L:1538
			row("dh_marble_pillar_73", -22, 1, -7887, 0), -- L:1539
			row("dh_marble_pillar_74", 22, 1, -7887, 0), -- L:1540
			row("dh_marble_pillar_75", -22, 1, -7937, 0), -- L:1541
			row("dh_marble_pillar_76", 22, 1, -7937, 0), -- L:1542
			row("dh_marble_pillar_77", -22, 1, -7987, 0), -- L:1543
			row("dh_marble_pillar_78", 22, 1, -7987, 0), -- L:1544
			row("dh_marble_pillar_79", -22, 1, -8037, 0), -- L:1545
			row("dh_marble_pillar_80", 22, 1, -8037, 0), -- L:1546
			row("dh_marble_pillar_81", -22, 1, -8087, 0), -- L:1547
			row("dh_marble_pillar_82", 22, 1, -8087, 0), -- L:1548
			row("dh_marble_pillar_83", -22, 1, -8137, 0), -- L:1549
			row("dh_marble_pillar_84", 22, 1, -8137, 0), -- L:1550
			row("dh_marble_pillar_85", -22, 1, -8187, 0), -- L:1551
			row("dh_marble_pillar_86", 22, 1, -8187, 0), -- L:1552
			row("dh_marble_pillar_87", -22, 1, -8237, 0), -- L:1553
			row("dh_marble_pillar_88", 22, 1, -8237, 0), -- L:1554
			row("dh_marble_pillar_89", -22, 1, -8287, 0), -- L:1555
			row("dh_marble_pillar_90", 22, 1, -8287, 0), -- L:1556
			row("dh_marble_pillar_91", -22, 1, -8337, 0), -- L:1557
			row("dh_marble_pillar_92", 22, 1, -8337, 0), -- L:1558
			row("dh_gold_cloud_03", -47.25, -9.52, -6097, -71.9), -- L:1559
			row("dh_gold_cloud_04", 84.5, -13.194, -6162, -167.1), -- L:1560
			row("dh_gold_cloud_05", -71, -10.303, -6227, -157.2), -- L:1561
			row("dh_gold_cloud_06", 101.125, -21.13, -6292, -112.8), -- L:1562
			row("dh_gold_cloud_07", -70.375, -18.888, -6357, 67.5), -- L:1563
			row("dh_gold_cloud_08", 81.25, -21.834, -6422, -36.4), -- L:1564
			row("dh_gold_cloud_09", -97.5, -19.916, -6487, -114.2), -- L:1565
			row("dh_gold_cloud_10", 101.375, -23.913, -6552, 110.8), -- L:1566
			row("dh_gold_cloud_11", -104.5, -25.976, -6617, 47.5), -- L:1567
			row("dh_gold_cloud_12", 67.75, -25.612, -6682, -110.6), -- L:1568
			row("dh_gold_cloud_13", -102.875, -22.886, -6747, 76.3), -- L:1569
			row("dh_gold_cloud_14", 106.375, -13.403, -6812, 63.1), -- L:1570
			row("dh_gold_cloud_15", -48.125, -14.721, -6877, 5.7), -- L:1571
			row("dh_gold_cloud_16", 96.875, -15.351, -6942, -89.6), -- L:1572
			row("dh_gold_cloud_17", -49, -20.037, -7007, -102.7), -- L:1573
			row("dh_gold_cloud_18", 106.875, -16.139, -7072, -148.3), -- L:1574
			row("dh_gold_cloud_19", -94.375, -13.355, -7137, -95.9), -- L:1575
			row("dh_gold_cloud_20", 81.875, -24.195, -7202, 16.3), -- L:1576
			row("dh_gold_cloud_21", -82.875, -21.952, -7267, -150.8), -- L:1577
			row("dh_gold_cloud_22", 57.625, -21.985, -7332, -136.8), -- L:1578
			row("dh_gold_cloud_23", -84.125, -11.369, -7397, 86.2), -- L:1579
			row("dh_gold_cloud_24", 103.375, -25.05, -7462, -111.4), -- L:1580
			row("dh_gold_cloud_25", -68.5, -11.745, -7527, -122.5), -- L:1581
			row("dh_gold_cloud_26", 96.375, -24.116, -7592, -29), -- L:1582
			row("dh_gold_cloud_27", -75, -11.187, -7657, 153), -- L:1583
			row("dh_gold_cloud_28", 100.625, -11.769, -7722, -98.2), -- L:1584
			row("dh_gold_cloud_29", -103.5, -10.553, -7787, 68.5), -- L:1585
			row("dh_gold_cloud_30", 90.375, -23.217, -7852, 45.1), -- L:1586
			row("dh_gold_cloud_31", -106.375, -8.814, -7917, 20.3), -- L:1587
			row("dh_gold_cloud_32", 45.375, -21.285, -7982, -21.3), -- L:1588
			row("dh_gold_cloud_33", -100.875, -8.782, -8047, 99.7), -- L:1589
			row("dh_gold_cloud_34", 53.875, -25.464, -8112, 169.1), -- L:1590
			row("dh_gold_cloud_35", -79.125, -23.452, -8177, 116.3), -- L:1591
			row("dh_gold_cloud_36", 73.625, -21.918, -8242, 19.8), -- L:1592
			row("dh_gold_cloud_37", -43.125, -24.317, -8307, -133.4), -- L:1593
			row("dh_gold_cloud_38", 72.75, -11.453, -8372, -97.9), -- L:1594
			row("dh_gold_cloud_39", -75.75, -13.393, -8437, 139.7), -- L:1595
			row("dh_gold_cloud_40", 82.875, -8.626, -8502, -82.6), -- L:1596
			row("dh_gold_cloud_41", -16, -9, -8412, 0), -- L:1598
			row("dh_gold_cloud_42", 16, -9, -8412, 0), -- L:1599
		},
	} :: { { Row } },
}

return HighwayScenery
