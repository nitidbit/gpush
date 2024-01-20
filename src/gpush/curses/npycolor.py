import curses
import npyscreen
import threading
import time

# Define a custom form
class TaskProgressForm(npyscreen.Form):
    def create(self):
        self.progress_bars = []

        for i in range(5):
            # Add a progress bar for each task
            # Use different color rules for each progress bar
            pb = self.add(npyscreen.TitleSlider, out_of=100, name=f"Task {i+1}", color='STANDOUT')
            self.progress_bars.append(pb)

    def update_progress(self, task_number, progress):
        if task_number < len(self.progress_bars):
            self.progress_bars[task_number].value = progress
            self.display()

def simulate_task_progress(form, task_number):
    for progress in range(101):
        form.update_progress(task_number, progress)
        time.sleep(0.1)  # Simulate time taken for the task

class TaskApp(npyscreen.NPSAppManaged):
    def onStart(self):
        self.addForm("MAIN", TaskProgressForm, name="Task Progress")

if __name__ == "__main__":
    curses.initscr()
    app = TaskApp()
    main_form = app.addForm("MAIN", TaskProgressForm, name="Task Progress")

    # Create and start threads for each task
    threads = []
    for i in range(5):
        thread = threading.Thread(target=simulate_task_progress, args=(main_form, i))
        thread.start()
        threads.append(thread)

    app.run()

    # Wait for all threads to finish
    for thread in threads:
        thread.join()
