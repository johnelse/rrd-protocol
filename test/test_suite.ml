(*
 * Copyright (C) Citrix Systems Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published
 * by the Free Software Foundation; version 2.1 only. with the special
 * exception on linking described in file LICENSE.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *)

open OUnit

let test_payload = Rrd_protocol.({
	timestamp = 1387867223L;
	datasources = [
		Rrd.Host,
		Ds.ds_make ~name:"test_int1"
			~description:"A test integer"
			~value:(Rrd.VT_Int64 1234L)
			~ty:Rrd.Gauge
			~default:true
			~units:"things" ();
		Rrd.SR "test_sr",
		Ds.ds_make ~name:"test_int2"
			~description:"A test integer"
			~value:(Rrd.VT_Int64 5678L)
			~ty:Rrd.Gauge
			~default:true
			~units:"things" ();
		Rrd.VM "test_vm",
		Ds.ds_make ~name:"test_int3"
			~description:"A test integer"
			~value:(Rrd.VT_Float 987.654)
			~ty:Rrd.Gauge
			~default:true
			~units:"things" ();
	];
})

let are_value_types_equal value1 value2 =
	match value1, value2 with
	| Rrd.VT_Int64 a, Rrd.VT_Int64 b -> a = b
	| Rrd.VT_Unknown, Rrd.VT_Unknown -> true
	| Rrd.VT_Float a, Rrd.VT_Float b ->
		let diff = abs_float (a -. b) in
		diff <= 0.01
	| _, _ -> false

let print_owner = function
	| Rrd.Host -> "Host"
	| Rrd.VM vm -> "VM " ^ vm
	| Rrd.SR sr -> "SR " ^ sr
let print_string x = x
let print_type = function
	| Rrd.Absolute -> "Absolute"
	| Rrd.Derive -> "Derive"
	| Rrd.Gauge -> "Gauge"
let print_value_type = function
	| Rrd.VT_Float x -> "Float " ^ (string_of_float x)
	| Rrd.VT_Int64 x -> "Float " ^ (Int64.to_string x)
	| Rrd.VT_Unknown -> "Unknown"

let assert_ds_equal (owner1, ds1) (owner2, ds2) =
	assert_equal ~printer:print_owner owner1 owner2;
	let open Ds in
	assert_equal ~printer:print_string ds1.ds_name ds2.ds_name;
	assert_equal ~printer:print_string ds1.ds_description ds2.ds_description;
	assert_equal
		~cmp:are_value_types_equal
		~printer:print_value_type
		ds1.ds_value
		ds2.ds_value;
	assert_equal ~printer:print_type ds1.ds_type ds2.ds_type;
	assert_equal ~printer:string_of_bool ds1.ds_default ds2.ds_default;
	assert_equal ~printer:string_of_float ds1.ds_min ds2.ds_min;
	assert_equal ~printer:string_of_float ds1.ds_max ds2.ds_max;
	assert_equal ~printer:print_string ds1.ds_units ds2.ds_units

let test_file_io protocol =
	bracket
		(fun () ->
			let shared_file =
				Filename.temp_file ~temp_dir:"/dev/shm" "test-metrics" ".tmp" in
			let _, writer = Rrd_writer.FileWriter.create shared_file protocol in
			let reader = Rrd_reader.FileReader.create shared_file protocol in
			writer, reader)
		(fun (writer, reader) ->
			(* Check that writing then reading the shared file gives the expected
			 * timestamp and datasources. *)
			writer.Rrd_writer.write_payload test_payload;
			let received_payload = reader.Rrd_reader.read_payload () in
			Rrd_protocol.(
				assert_equal
					test_payload.timestamp
					received_payload.timestamp;
				assert_equal
					(List.length test_payload.datasources)
					(List.length received_payload.datasources);
				List.iter2
					assert_ds_equal
					test_payload.datasources
					received_payload.datasources))
		(fun (writer, reader) ->
			reader.Rrd_reader.cleanup ();
			writer.Rrd_writer.cleanup ())
		()

let base_suite =
	"test_suite" >:::
		[
			"test_file_io_v1" >:: (fun () -> test_file_io Rrd_protocol_v1.protocol);
			"test_file_io_v2" >:: (fun () -> test_file_io Rrd_protocol_v2.protocol);
		]

let _ = run_test_tt_main base_suite