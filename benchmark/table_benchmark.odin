package benchmark

import "core:fmt"
import "core:time"
import "core:math"

import olox "../src"


main :: proc() {
using olox
	set_times: [100]f64
	get_times: [100]f64
	N :: 100000

	//Test 1 : Insertion performance
	{
		table := Table{}
		defer free_table(&table)

		for i in 0 ..< 100 {
			start := time.now()
			for j in 0 ..< N {
				table_set(&table, number_val(f64(j)), number_val(f64(j * 2)))
			}
			end := time.now()
			duration_ns := time.duration_nanoseconds(time.diff(start, end))
			set_times[i] = f64(duration_ns) / 1_000_000.0  // Convert nanoseconds to milliseconds
		}

	}
	//Test 2 : Lookup performance 
	{
		table := Table{}
		defer free_table(&table)

		for i in 0 ..< N {
			table_set(&table, number_val(f64(i)), number_val(f64(i * 2)))
		}

		for i in 0 ..< 100 {
			start := time.now()
			for j in 0 ..< N {
				table_get(&table, number_val(f64(j)))
			}
			end := time.now()
			duration_ns := time.duration_nanoseconds(time.diff(start, end))
			get_times[i] = f64(duration_ns) / 1_000_000.0  // Convert nanoseconds to milliseconds
		}

	}

	 print_benchmark_table("Insertion (ms)", set_times[:])
	print_benchmark_table("Lookup (ms)", get_times[:])

}

print_benchmark_table :: proc(test_name: string, times: []f64) {
    if len(times) == 0 do return
    
    min_time := times[0]
    max_time := times[0]
    total := f64(0)
    
    for time in times {
        if time < min_time do min_time = time
        if time > max_time do max_time = time
        total += time
    }
    
    avg_time := total / f64(len(times))
    
    variance := f64(0)
    for time in times {
        diff := time - avg_time
        variance += diff * diff
    }
    std_dev := math.sqrt(variance / f64(len(times)))
    

   times_str := fmt.aprintf("%d", len(times))

    min_str := fmt.aprintf("%.2f", min_time)
    max_str := fmt.aprintf("%.2f", max_time)
    avg_str := fmt.aprintf("%.2f", avg_time)
    std_str := fmt.aprintf("%.2f", std_dev)
    defer delete(min_str)
    defer delete(max_str)
    defer delete(avg_str)
    defer delete(std_str)
    
    fmt.println()
    fmt.printf("┌─────────────────────────────────────────────────────┐\n")
    fmt.printf("│ %-51s │\n", test_name)
    fmt.printf("├─────────────────────────────────────────────────────┤\n")
    fmt.printf("│ Samples:     %38s │\n", times_str)
    fmt.printf("│ Min:         %38s │\n", min_str)
    fmt.printf("│ Max:         %38s │\n", max_str)
    fmt.printf("│ Average:     %38s │\n", avg_str)
    fmt.printf("│ Std Dev:     %38s │\n", std_str)
    fmt.printf("└─────────────────────────────────────────────────────┘\n")
}
