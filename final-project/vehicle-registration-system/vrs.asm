; =============================================================================
; Vehicle Registration System (vrs.asm)
;
; Description:
;   Simple in-memory vehicle registration system implemented in x86 (IA-32) NASM
;   assembly. The program stores up to 20 records in parallel arrays: owner names
;   and plate numbers. Basic operations supported via a text menu:
;     - Add Vehicle
;     - Delete Vehicle by Plate
;     - Delete All Vehicles by Owner
;     - Search by Plate
;     - Search by Owner
;     - Display All Vehicles (grouped by owner)
;
; Data layout and limits:
;   - owner_names: 20 entries * 64 bytes each (fixed-size, null-terminated)
;   - plate_numbers: 20 entries * 32 bytes each (fixed-size, null-terminated)
;   - vehicle_count: dword holding the current number of stored records (0..20)
;   - Arrays are parallel: index i corresponds to owner_names[i] and plate_numbers[i]
;
; I/O / ABI:
;   - Uses C library functions _printf and _scanf (cdecl, leading underscore used
;     for typical MSVC/Mingw symbol names on 32-bit targets).
;   - Functions push arguments onto the stack and call _printf/_scanf directly.
;   - Each routine in this file sets up a stack frame (push ebp / mov ebp, esp)
;     and restores it before returning.
;
; Algorithm notes and behavior:
;   - Searches are linear, byte-by-byte string comparisons; exact match only.
;   - Adding a vehicle checks for duplicated plate numbers (plates are unique).
;   - Deleting shifts later records down to keep arrays compact.
;   - Display and search routines treat single vs multiple-owner-plate results
;     differently for nicer output formatting.
;
; Build (example) / runtime:
;   - This file is written for 32-bit NASM and a C runtime (Windows/Mingw/MSVC).
;   - Example (when using a 32-bit toolchain):
;       nasm -f win32 vrs.asm -o vrs.obj
;       gcc vrs.obj -o vrs.exe         # 32-bit MinGW gcc, or link with MSVC tools
;
; Limitations and TODOs:
;   - Max records: 20. No dynamic allocation.
;   - Fixed-width buffers; input larger than buffer will be truncated by scanf
;     format (the format specifiers limit input sizes in the .data section).
;   - No persistent storage; all data is lost when the program exits.
;
; =============================================================================
section .data
    menu_text db "=== Vehicle Registration System ===", 13, 10, 13
            db "1. Add Vehicle", 13, 10
            db "2. Delete Vehicle by Plate", 13, 10
            db "3. Delete All Vehicles by Owner", 13, 10
            db "4. Search by Plate", 13, 10
            db "5. Search by Owner", 13, 10
            db "6. Display All Vehicles", 13, 10
            db "0. Exit", 13, 10
            db 0
    prompt_text db "Enter choice (0-6): ", 0
    scan_int    db "%d", 0
    choice      dd 0
    reg_header  db 13, 10, "=== Vehicle Registration Details ===", 13, 10, 0
    prompt_owner db 13, "Enter Owner Name: ", 0
    prompt_plate db 13, "Enter Plate Number: ", 0
    scan_owner   db " %63[^", 10, "]", 0
    scan_plate   db " %31[^", 10, "]", 0
    add_success  db 13, 10, 'Vehicle added successfully!', 13, 10, 10, 0
    err_choice   db 13, 10, 'Invalid choice. Please enter 0-6.', 13, 10, 0
    err_duplicate db 13, 10, 'Error: Plate number already exists. Enter a different plate.', 13, 10, 0
    del_success  db 13, 10, 'Vehicle deleted successfully!', 13, 10, 0
    not_found    db 13, 10, 'No vehicle found.', 13, 10, 0
    prompt_owner_search db 13, 10, 'Enter Owner Name: ', 0
    fmt_str     db '%s', 0
    lbl_owner   db 'Owner: ', 0
    lbl_plate   db 'Plate Number: ', 0
    lbl_plates  db 'Plate Numbers:', 13, 10, 0
    crlf        db 13, 10, 0
    del_owner_success db 13, 10, 'All vehicles for owner deleted successfully!', 13, 10, 0

section .bss
    owner_inp     resb 64
    plate_inp     resb 32
    owner_names   resb 64 * 20
    plate_numbers resb 32 * 20
    vehicle_count resd 1
    tmp_index     resd 1
    loop_i        resd 1
    inner_j       resd 1
    inner_k       resd 1
    match_count   resd 1

section .text
    global _main
    extern _printf
    extern _scanf
    extern _atoi

; -----------------------------------------------------------------------------
; _main
; Entry point for the program. Presents a textual menu, reads an integer choice
; from the user (stored in variable `choice`), validates it, and dispatches to
; the appropriate handler routine. Loops until the user selects 0 (Exit).
;
; Stack / calling convention:
;   - cdecl style: arguments are pushed right-to-left before calling printf/scanf
;   - _main uses a standard stack frame (push ebp / mov ebp, esp).
; Side-effects:
;   - Calls AddVehicle, DeleteByPlate, DeleteByOwner, SearchByPlate,
;     SearchByOwner, DisplayAll as needed which mutate or read global arrays.
; -----------------------------------------------------------------------------
_main:
    push ebp
    mov ebp, esp

main_menu:
    ; print menu
    push dword menu_text
    call _printf
    add esp, 4

    ; print prompt (no newline)
    push dword prompt_text
    call _printf
    add esp, 4

    ; read integer choice
    push dword choice
    push dword scan_int
    call _scanf
    add esp, 8

    mov eax, [choice]
    ; validate choice in range 0..6
    cmp eax, 0
    jl .invalid_choice
    cmp eax, 6
    jg .invalid_choice

    ; handle exit
    cmp eax, 0
    je .exit_program

    ; handle Add Vehicle (1)
    cmp eax, 1
    jne .check_delete_by_plate
    call AddVehicle
    jmp main_menu

.check_delete_by_plate:
    ; handle Delete Vehicle by Plate (2)
    cmp eax, 2
    jne .check_delete_by_owner
    call DeleteByPlate
    jmp main_menu

.check_delete_by_owner:
    ; handle Delete All Vehicles by Owner (3)
    cmp eax, 3
    jne .check_search_by_plate
    call DeleteByOwner
    jmp main_menu

.check_search_by_plate:
    ; handle Search by Plate (4)
    cmp eax, 4
    jne .check_search_by_owner
    call SearchByPlate
    jmp main_menu

.check_search_by_owner:
    ; handle Search by Owner (5)
    cmp eax, 5
    jne .check_display_all
    call SearchByOwner
    jmp main_menu

.check_display_all:
    ; handle Display All Vehicles (6)
    cmp eax, 6
    jne .after_menu
    call DisplayAll
    jmp main_menu

.after_menu:
    ; unreachable in practice (choice already validated as 0..6); re-display menu
    jmp main_menu

.invalid_choice:
    push dword err_choice
    call _printf
    add esp, 4
    jmp main_menu

.exit_program:
    mov esp, ebp
    pop ebp
    ret

; -----------------------------------------------------------------------------
; SearchByPlate
; Prompt the user for a plate number and perform a linear search through the
; `plate_numbers` array. If a match is found, print the Owner and Plate Number
; for the matched record. If none found, print the `not_found` message.
;
; Inputs:
;   - Reads plate string into buffer `plate_inp` using `scan_plate` format.
;   - Uses `vehicle_count` to limit the search to existing records.
; Algorithm:
;   - For i from 0 to vehicle_count-1 compare bytes of plate_inp and
;     plate_numbers[i] byte-by-byte until a mismatch or a terminating NUL.
;   - On match: set `tmp_index` := i and print owner and plate using `fmt_str`.
; Side-effects:
;   - No mutation of arrays, only prints to stdout.
; -----------------------------------------------------------------------------
SearchByPlate:
    push ebp
    mov ebp, esp

    ; prompt for plate
    push dword prompt_plate
    call _printf
    add esp, 4
    lea eax, [plate_inp]
    push eax
    push dword scan_plate
    call _scanf
    add esp, 8

    ; search for plate
    mov ecx, [vehicle_count]
    xor edx, edx
    test ecx, ecx
    jz .sbp_not_found
.sbp_loop:
    mov eax, edx
    imul eax, 32
    lea edi, [plate_numbers + eax]
    lea esi, [plate_inp]
.sbp_cmp:
    mov al, [esi]
    mov ah, [edi]
    cmp al, ah
    jne .sbp_next
    cmp al, 0
    je .sbp_found
    inc esi
    inc edi
    jmp .sbp_cmp
.sbp_next:
    inc edx
    cmp edx, ecx
    jl .sbp_loop
    jmp .sbp_not_found

.sbp_found:
    ; save matched index and print Owner: <owner_names[idx]>\n
    mov [tmp_index], edx
    push dword lbl_owner
    call _printf
    add esp, 4
    mov eax, [tmp_index]
    imul eax, 64
    lea eax, [owner_names + eax]
    push eax
    push dword fmt_str
    call _printf
    add esp, 8
    ; newline
    push dword crlf
    call _printf
    add esp, 4
    
    ; print Plate Number: <plate_numbers[idx]>\n
    push dword lbl_plate
    call _printf
    add esp, 4
    mov eax, [tmp_index]
    imul eax, 32
    lea eax, [plate_numbers + eax]
    push eax
    push dword fmt_str
    call _printf
    add esp, 8
    ; newline
    push dword crlf
    call _printf
    add esp, 4
    jmp .sbp_done

.sbp_not_found:
    push dword not_found
    call _printf
    add esp, 4

.sbp_done:
    mov esp, ebp
    pop ebp
    ret

; -----------------------------------------------------------------------------
; SearchByOwner
; Prompt for an owner name and list all plates registered to that owner.
; Behavior:
;   - First pass: count how many records match the entered owner string.
;   - If zero matches: print `not_found`.
;   - If exactly one match: print the single plate with label `Plate Number:`.
;   - If multiple matches: print `Plate Numbers:` header then list each plate
;     on its own line.
;
; Inputs:
;   - Reads owner name into `owner_inp` using `scan_owner`.
; Side-effects:
;   - Only reads arrays and prints; does not modify stored records.
; -----------------------------------------------------------------------------
SearchByOwner:
    push ebp
    mov ebp, esp

    ; prompt for owner name
    push dword prompt_owner_search
    call _printf
    add esp, 4
    lea eax, [owner_inp]
    push eax
    push dword scan_owner
    call _scanf
    add esp, 8

    ; first pass: count matches
    mov ecx, [vehicle_count]
    xor edx, edx            ; edx = i
    xor ebx, ebx            ; ebx = match_count
    test ecx, ecx
    jz .sbo_no_match
.sbo_count_loop:
    mov eax, edx
    imul eax, 64
    lea esi, [owner_names + eax]
    lea edi, [owner_inp]
.sbo_cmp_count:
    mov al, [esi]
    mov ah, [edi]
    cmp al, ah
    jne .sbo_next_count
    cmp al, 0
    je .sbo_inc_count
    inc esi
    inc edi
    jmp .sbo_cmp_count
.sbo_next_count:
    inc edx
    cmp edx, ecx
    jl .sbo_count_loop
    jmp .sbo_after_count
.sbo_inc_count:
    inc ebx
    inc edx
    cmp edx, ecx
    jl .sbo_count_loop
.sbo_after_count:
    test ebx, ebx
    jz .sbo_no_match

    ; print Owner header
    push dword lbl_owner
    call _printf
    add esp, 4
    lea eax, [owner_inp]
    push eax
    push dword fmt_str
    call _printf
    add esp, 8
    ; newline after Owner line
    push dword crlf
    call _printf
    add esp, 4

    cmp ebx, 1
    jne .sbo_many
    ; exactly one: print Plate Number: <plate>
    ; find again and print
    mov ecx, [vehicle_count]
    xor edx, edx
.sbo_find_one:
    mov eax, edx
    imul eax, 64
    lea esi, [owner_names + eax]
    lea edi, [owner_inp]
.sbo_cmp_one:
    mov al, [esi]
    mov ah, [edi]
    cmp al, ah
    jne .sbo_next_one
    cmp al, 0
    je .sbo_print_one
    inc esi
    inc edi
    jmp .sbo_cmp_one
.sbo_next_one:
    inc edx
    cmp edx, ecx
    jl .sbo_find_one
    jmp .sbo_done
.sbo_print_one:
    mov [tmp_index], edx
    push dword lbl_plate
    call _printf
    add esp, 4
    mov eax, [tmp_index]
    imul eax, 32
    lea eax, [plate_numbers + eax]
    push eax
    push dword fmt_str
    call _printf
    add esp, 8
    ; newline
    push dword crlf
    call _printf
    add esp, 4
    jmp .sbo_done

.sbo_many:
    ; print header "Plate Numbers:" then list each plate on its own line
    push dword lbl_plates
    call _printf
    add esp, 4

    mov ecx, [vehicle_count]
    mov dword [loop_i], 0
.sbo_list_loop:
    mov eax, [loop_i]
    imul eax, 64
    lea esi, [owner_names + eax]
    lea edi, [owner_inp]
.sbo_cmp_many:
    mov al, [esi]
    mov ah, [edi]
    cmp al, ah
    jne .sbo_next_list
    cmp al, 0
    je .sbo_print_plate
    inc esi
    inc edi
    jmp .sbo_cmp_many
.sbo_print_plate:
    mov eax, [loop_i]
    imul eax, 32
    lea eax, [plate_numbers + eax]
    push eax
    push dword fmt_str
    call _printf
    add esp, 8
    ; newline per plate
    push dword crlf
    call _printf
    add esp, 4
    
.sbo_next_list:
    mov eax, [loop_i]
    inc eax
    mov [loop_i], eax
    mov ecx, [vehicle_count]
    cmp eax, ecx
    jl .sbo_list_loop
    jmp .sbo_done

.sbo_no_match:
    push dword not_found
    call _printf
    add esp, 4

.sbo_done:
    mov esp, ebp
    pop ebp
    ret

; -----------------------------------------------------------------------------
; DisplayAll
; Print all stored vehicles grouped by owner. For each unique owner:
;   - If the owner has a single plate, print the `Plate Number:` line.
;   - If the owner has multiple plates, print a `Plate Numbers:` header and
;     then print each plate on its own line.
;
; Implementation notes:
;   - Iterates through records with index `loop_i` and skips owners that were
;     already printed by comparing previous entries (inner_j) to detect
;     duplicates.
; -----------------------------------------------------------------------------
DisplayAll:
    push ebp
    mov ebp, esp

    mov ecx, [vehicle_count]
    test ecx, ecx
    jnz .da_iter
    push dword not_found
    call _printf
    add esp, 4
    jmp .da_done

.da_iter:
    mov dword [loop_i], 0
.da_loop:
    ; i < count?
    mov eax, [loop_i]
    mov ecx, [vehicle_count]
    cmp eax, ecx
    jge .da_done

    ; skip if owner at i already seen (exists at j < i)
    mov dword [inner_j], 0
.check_seen_loop:
    mov edx, [inner_j]
    cmp edx, [loop_i]
    jge .not_seen
    ; compare owner_names[j] vs owner_names[i]
    mov eax, [inner_j]
    imul eax, 64
    lea esi, [owner_names + eax]
    mov eax, [loop_i]
    imul eax, 64
    lea edi, [owner_names + eax]
.cmp_seen:
    mov al, [esi]
    mov ah, [edi]
    cmp al, ah
    jne .seen_next
    cmp al, 0
    je .seen_duplicate
    inc esi
    inc edi
    jmp .cmp_seen
.seen_next:
    mov eax, [inner_j]
    inc eax
    mov [inner_j], eax
    jmp .check_seen_loop
.seen_duplicate:
    ; already processed this owner -> i++ and continue
    mov eax, [loop_i]
    inc eax
    mov [loop_i], eax
    jmp .da_loop

.not_seen:
    ; count matches for owner at i across all records
    mov dword [match_count], 0
    mov dword [inner_k], 0
.count_loop:
    mov edx, [inner_k]
    mov ecx, [vehicle_count]
    cmp edx, ecx
    jge .after_count
    ; compare owner_names[k] vs owner_names[i]
    mov eax, [inner_k]
    imul eax, 64
    lea esi, [owner_names + eax]
    mov eax, [loop_i]
    imul eax, 64
    lea edi, [owner_names + eax]
.cmp_count:
    mov al, [esi]
    mov ah, [edi]
    cmp al, ah
    jne .next_k
    cmp al, 0
    je .inc_match
    inc esi
    inc edi
    jmp .cmp_count
.inc_match:
    mov eax, [match_count]
    inc eax
    mov [match_count], eax
    mov eax, [inner_k]
    inc eax
    mov [inner_k], eax
    jmp .count_loop
.next_k:
    mov eax, [inner_k]
    inc eax
    mov [inner_k], eax
    jmp .count_loop

.after_count:
    ; print Owner line
    push dword lbl_owner
    call _printf
    add esp, 4
    mov eax, [loop_i]
    imul eax, 64
    lea eax, [owner_names + eax]
    push eax
    push dword fmt_str
    call _printf
    add esp, 8
    ; newline
    push dword crlf
    call _printf
    add esp, 4

    ; decide single vs multiple
    mov eax, [match_count]
    cmp eax, 1
    jne .print_many

    ; single: print the single plate for this owner (the record at i)
    push dword lbl_plate
    call _printf
    add esp, 4
    mov eax, [loop_i]
    imul eax, 32
    lea eax, [plate_numbers + eax]
    push eax
    push dword fmt_str
    call _printf
    add esp, 8
    push dword crlf
    call _printf
    add esp, 4
    jmp .advance_i

.print_many:
    ; header and list all plates for this owner
    push dword lbl_plates
    call _printf
    add esp, 4
    mov dword [inner_k], 0
.list_loop:
    mov edx, [inner_k]
    mov ecx, [vehicle_count]
    cmp edx, ecx
    jge .advance_i
    ; compare owner_names[k] vs owner_names[i]
    mov eax, [inner_k]
    imul eax, 64
    lea esi, [owner_names + eax]
    mov eax, [loop_i]
    imul eax, 64
    lea edi, [owner_names + eax]
.cmp_list:
    mov al, [esi]
    mov ah, [edi]
    cmp al, ah
    jne .next_list
    cmp al, 0
    je .print_plate_item
    inc esi
    inc edi
    jmp .cmp_list
.print_plate_item:
    mov eax, [inner_k]
    imul eax, 32
    lea eax, [plate_numbers + eax]
    push eax
    push dword fmt_str
    call _printf
    add esp, 8
    push dword crlf
    call _printf
    add esp, 4
.next_list:
    mov eax, [inner_k]
    inc eax
    mov [inner_k], eax
    jmp .list_loop

.advance_i:
    mov eax, [loop_i]
    inc eax
    mov [loop_i], eax
    jmp .da_loop

.da_done:
    mov esp, ebp
    pop ebp
    ret

; -----------------------------------------------------------------------------
; DeleteByOwner
; Prompt for an owner name, then remove all records whose owner matches the
; entered name. To delete a matching record the code shifts all subsequent
; records down by copying bytes (owner_names and plate_numbers) and then
; decrements `vehicle_count`.
;
; Inputs:
;   - Reads owner into `owner_inp` via `scan_owner`.
; Side-effects:
;   - Mutates `owner_names`, `plate_numbers`, and `vehicle_count`.
; Notes:
;   - deleted_count is stored in `tmp_index` and used to display a success
;     message if any deletions occurred.
; -----------------------------------------------------------------------------
DeleteByOwner:
    push ebp
    mov ebp, esp

    ; prompt for owner
    push dword prompt_owner_search
    call _printf
    add esp, 4
    lea eax, [owner_inp]
    push eax
    push dword scan_owner
    call _scanf
    add esp, 8

    mov dword [loop_i], 0        ; i = 0
    mov dword [tmp_index], 0     ; deleted_count = 0
    mov ecx, [vehicle_count]
    test ecx, ecx
    jz .owner_done

.owner_scan:
    mov eax, [loop_i]
    cmp eax, ecx
    jge .owner_done

    ; compare owner_names[i] with owner_inp
    mov eax, [loop_i]
    imul eax, 64
    lea esi, [owner_names + eax]
    lea edi, [owner_inp]
.cmp_owner:
    mov al, [esi]
    mov ah, [edi]
    cmp al, ah
    jne .no_match_owner
    cmp al, 0
    je .match_owner
    inc esi
    inc edi
    jmp .cmp_owner

.match_owner:
    ; shift down from i+1..count-1 into i..count-2 for both arrays
    mov ebx, [loop_i]            ; k = i
.shift_loop:
    mov eax, [vehicle_count]
    dec eax                      ; last_index
    cmp ebx, eax
    jge .dec_and_continue

    ; copy owner_names: dst=k*64, src=(k+1)*64, 64 bytes
    mov edx, ebx
    imul edx, 64
    lea edi, [owner_names + edx]
    mov edx, ebx
    inc edx
    imul edx, 64
    lea esi, [owner_names + edx]
    mov ecx, 64
.copy64:
    mov al, [esi]
    mov [edi], al
    inc esi
    inc edi
    dec ecx
    jnz .copy64

    ; copy plate_numbers: dst=k*32, src=(k+1)*32, 32 bytes
    mov edx, ebx
    imul edx, 32
    lea edi, [plate_numbers + edx]
    mov edx, ebx
    inc edx
    imul edx, 32
    lea esi, [plate_numbers + edx]
    mov ecx, 32
.copy32:
    mov al, [esi]
    mov [edi], al
    inc esi
    inc edi
    dec ecx
    jnz .copy32

    inc ebx
    jmp .shift_loop

.dec_and_continue:
    ; decrement count, increment deleted_count, don't advance i
    mov eax, [vehicle_count]
    dec eax
    mov [vehicle_count], eax
    mov eax, [tmp_index]
    inc eax
    mov [tmp_index], eax
    mov ecx, [vehicle_count]
    jmp .owner_scan

.no_match_owner:
    ; i++
    mov eax, [loop_i]
    inc eax
    mov [loop_i], eax
    jmp .owner_scan

.owner_done:
    mov eax, [tmp_index]
    test eax, eax
    jz .owner_not_found
    push dword del_owner_success
    call _printf
    add esp, 4
    jmp .owner_exit

.owner_not_found:
    push dword not_found
    call _printf
    add esp, 4

.owner_exit:
    mov esp, ebp
    pop ebp
    ret

; -----------------------------------------------------------------------------
; AddVehicle
; Prompt the user for Owner name and Plate number and add a new record if
; there is capacity and if the plate does not already exist.
;
; Steps:
;   - Read owner into `owner_inp`.
;   - Read plate into `plate_inp` (loops prompting until a unique plate is
;     entered; duplicate plates trigger `err_duplicate` and re-prompt).
;   - Copy owner (up to 64 bytes including terminating NUL) into the next
;     slot in `owner_names` and copy plate (up to 32 bytes) into
;     `plate_numbers`.
;   - Increment `vehicle_count` and print `add_success`.
;
; Side-effects:
;   - Mutates `owner_names`, `plate_numbers`, and `vehicle_count`.
; -----------------------------------------------------------------------------
AddVehicle:
    push ebp
    mov ebp, esp

    ; header
    push dword reg_header
    call _printf
    add esp, 4

    ; prompt owner
    push dword prompt_owner
    call _printf
    add esp, 4
    lea eax, [owner_inp]
    push eax
    push dword scan_owner
    call _scanf
    add esp, 8

    ; prompt plate (loop until unique)
.plate_prompt:
    push dword prompt_plate
    call _printf
    add esp, 4
    lea eax, [plate_inp]
    push eax
    push dword scan_plate
    call _scanf
    add esp, 8

    ; check for duplicate plate numbers
    mov ecx, [vehicle_count]    ; number of vehicles
    xor edx, edx                ; edx = index = 0
    test ecx, ecx
    jz .save_record             ; no records yet
.dup_loop:
    ; edi -> existing plate, esi -> input plate
    mov eax, edx
    imul eax, 32
    lea edi, [plate_numbers + eax]
    lea esi, [plate_inp]
.cmp_bytes:
    mov al, [esi]
    mov bl, [edi]
    cmp al, bl
    jne .not_equal
    cmp al, 0
    je .duplicate_found         ; both zero => equal strings
    inc esi
    inc edi
    jmp .cmp_bytes
.not_equal:
    inc edx
    cmp edx, ecx
    jl .dup_loop
    jmp .save_record

.duplicate_found:
    push dword err_duplicate
    call _printf
    add esp, 4
    jmp .plate_prompt

    ; save if capacity available
.save_record:
    mov ecx, [vehicle_count]
    cmp ecx, 20
    jge .done

    ; compute base pointers for owner: index * 64
    mov edx, ecx
    imul edx, 64
    lea edi, [owner_names + edx]
    lea esi, [owner_inp]
    mov ebx, 64
.copy_owner:
    mov al, [esi]
    mov [edi], al
    cmp al, 0
    je .pad_owner
    inc esi
    inc edi
    dec ebx
    jnz .copy_owner
    jmp .owner_done
.pad_owner:
    inc edi
    dec ebx
    jz .owner_done
    mov byte [edi-1], 0
    jmp .pad_owner
.owner_done:

    ; plate copy: index * 32
    mov edx, [vehicle_count]
    imul edx, 32
    lea edi, [plate_numbers + edx]
    lea esi, [plate_inp]
    mov ebx, 32
.copy_plate:
    mov al, [esi]
    mov [edi], al
    cmp al, 0
    je .pad_plate
    inc esi
    inc edi
    dec ebx
    jnz .copy_plate
    jmp .plate_done
.pad_plate:
    inc edi
    dec ebx
    jz .plate_done
    mov byte [edi-1], 0
    jmp .pad_plate
.plate_done:

    ; increment count
    mov eax, [vehicle_count]
    inc eax
    mov [vehicle_count], eax

    ; success message
    push dword add_success
    call _printf
    add esp, 4

.done:
    mov esp, ebp
    pop ebp
    ret

; -----------------------------------------------------------------------------
; DeleteByPlate
; Prompt for a plate number and remove the matching record (if any). If the
; matched record is not the last one, subsequent records are shifted down to
; preserve contiguous storage. After deletion `vehicle_count` is decremented.
;
; Inputs:
;   - Reads plate into `plate_inp` via `scan_plate`.
; Side-effects:
;   - Mutates `owner_names`, `plate_numbers`, and `vehicle_count` on success.
; -----------------------------------------------------------------------------
DeleteByPlate:
    push ebp
    mov ebp, esp

    ; prompt for plate
    push dword prompt_plate
    call _printf
    add esp, 4
    lea eax, [plate_inp]
    push eax
    push dword scan_plate
    call _scanf
    add esp, 8

    ; search for plate
    mov ecx, [vehicle_count]
    xor edx, edx                ; edx = index = 0
    test ecx, ecx
    jz .no_match
.search_loop:
    mov eax, edx
    imul eax, 32
    lea edi, [plate_numbers + eax]
    lea esi, [plate_inp]
.cmp_loop:
    mov al, [esi]
    mov bl, [edi]
    cmp al, bl
    jne .next_record
    cmp al, 0
    je .found_match
    inc esi
    inc edi
    jmp .cmp_loop
.next_record:
    inc edx
    cmp edx, ecx
    jl .search_loop
    jmp .no_match

.found_match:
    ; edx = matched index, ecx = count
    mov eax, ecx
    dec eax                     ; eax = last_index
    cmp edx, eax
    jge .dec_count              ; if matched is last, just dec count

    ; shift records down from edx+1 .. last to edx .. last-1
    ; shift owner_names and plate_numbers (byte copies)
    mov ebx, edx                ; ebx = k = matched index
.shift_loop:
    ; owner_names: dst = k*64, src = (k+1)*64, copy 64 bytes
    mov eax, ebx
    imul eax, 64
    lea edi, [owner_names + eax]
    mov eax, ebx
    inc eax
    imul eax, 64
    lea esi, [owner_names + eax]
    mov ecx, 64
.copy_owner_shift:
    mov al, [esi]
    mov [edi], al
    inc esi
    inc edi
    dec ecx
    jnz .copy_owner_shift

    ; plate_numbers: dst = k*32, src = (k+1)*32, copy 32 bytes
    mov eax, ebx
    imul eax, 32
    lea edi, [plate_numbers + eax]
    mov eax, ebx
    inc eax
    imul eax, 32
    lea esi, [plate_numbers + eax]
    mov ecx, 32
.copy_plate_shift:
    mov al, [esi]
    mov [edi], al
    inc esi
    inc edi
    dec ecx
    jnz .copy_plate_shift

    inc ebx
    mov ecx, [vehicle_count]
    mov eax, ecx
    dec eax                     ; eax = last_index
    cmp ebx, eax
    jl .shift_loop

.dec_count:
    mov eax, [vehicle_count]
    dec eax
    mov [vehicle_count], eax
    push dword del_success
    call _printf
    add esp, 4
    jmp .done

.no_match:
    push dword not_found
    call _printf
    add esp, 4

.done:
    mov esp, ebp
    pop ebp
    ret