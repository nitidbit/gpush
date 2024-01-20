import sys
import curses
import npyscreen
import subprocess
import threading
import time

class TestApp(npyscreen.NPSAppManaged):
    def onStart(self):
        print("hi jay")
        #        self.addForm("MAIN", MainForm, name="aaa Test Runner"#, max_width=10)
        #        self.addForm("aaaaaa2nd", MainForm, name="aaaaaaaa2nd# Test Runner")
        
class MainForm(npyscreen.Form):
    def create(self):
        self.test_output = self.add(npyscreen.TitleText, name="Test Output:", value="Starting tests...")
        self.test_output2 = self.add(npyscreen.TitleText, name="Test Output 2:", value="Starting more tests...")

    def afterEditing(self):
        self.parentApp.setNextForm(None)

    def update_progress(self, progress):
        self.value = progress
        self.display()

def run_tests(form, num):
    # exec a script
    # capture the output
    result = subprocess.run(['./sleepy.sh'], stdout=subprocess.PIPE)
    sys.exit()
    for i in range(1, 11):
        self.test_output.value = f"Running test {i}/10"
        form.update_progress(result)
 #       self.test_output.value = result.stdout
#        self.display()
#        time.sleep(1)  # Simulate time taken for each test

if __name__ == "__main__":
    curses.initscr()
    app = TestApp()
    main_form = app.addForm("MAIN", MainForm, name="bbbb Test Runner")
    second_form = app.addForm("2nd", MainForm, name="2nd Test Runner")
    
    # Create and start threads for each task
    threads = []

    for i in range(5):
        thread = threading.Thread(target=run_tests, args=(main_form, i))
        thread.start()
        threads.append(thread)

    app.run()

    # Wait for all threads to finish
    for thread in threads:
        thread.join()

        # Create and start threads for each task
#     threads = []
#     for i in range(5):
#         print(i)
#         thread = threading.Thread(target=run_tests, args=(main
# _form, i))
#         thread.start()
#         threads.append(thread)

#     app.run()

#     # Wait for all threads to finish
#     for thread in threads:
#         thread.join()
