import urwid
import threading
import time

def update_test_progress(main_loop, text_widget, current_test, total_tests):
    for i in range(current_test, total_tests + 1):
        text_widget.set_text(f"Running test {i}/{total_tests}")
        main_loop.draw_screen()  # Redraw the screen with updated text
        time.sleep(1)  # Simulate time taken for each test
    
    # Schedule the main loop to stop in 1 second
    main_loop.set_alarm_in(1, exit_program)

def exit_program(main_loop, user_data):
    main_loop.stop()

def urwid_main():
    test_output = urwid.Text("Starting tests...")
    filler = urwid.Filler(test_output, valign='top')
    loop = urwid.MainLoop(filler)

    # Start a separate thread for running tests and updating UI
    test_thread = threading.Thread(target=update_test_progress, args=(loop, test_output, 1, 10))
    test_thread.start()

    loop.run()

if __name__ == "__main__":
    urwid_main()