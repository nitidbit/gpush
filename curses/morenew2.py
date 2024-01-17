import time
import npyscreen
import subprocess
import threading
import queue

class CommandForm(npyscreen.Form):
    def create(self):
        self.output_field = self.add(npyscreen.MultiLineEdit, value="", editable=False, max_height=-2)
        self.output_field.value = "one"
        self.error_field = self.add(npyscreen.MultiLineEdit, value="", editable=False, color='DANGER')
        self.error_field.value = "two"
        self.cmd_queue = queue.Queue()
        self.cmd_thread = threading.Thread(target=self.run_command, args=("./sleepy.sh",))
        self.cmd_thread.start()
        self.update_thread = threading.Thread(target=self.update_ui)
        self.update_thread.daemon = True
        self.update_thread.start()
        
    def run_command(self, command, *args):
        process = subprocess.Popen([command, *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
        for line in process.stdout:
            self.cmd_queue.put(line)
#            self.queue_event(npyscreen.Event("update_output", payload=line))
        for line in process.stderr:
            self.cmd_queue.put(('error', line))

    def update_ui(self):
        while True:
            try:
                item = self.cmd_queue.get_nowait()
                if isinstance(item, tuple) and item[0] == 'error':
                    self.error_field.value += item[1]
                else:
                    self.output_field.value += item
                self.display()
            except queue.Empty:
                time.sleep(0.1)
            
    def while_waiting(self):
        try:
            while True:
                item = self.cmd_queue.get_nowait()
                if isinstance(item, tuple) and item[0] == 'error':
                    self.error_field.value += item[1]
                else:
                    self.output_field.value += item
                    self.display()

        except queue.Empty:
            pass

    def handle_event_update_output(self, event):
        self.output_field.value += event.payload
        self.display()

class CommandApp(npyscreen.NPSAppManaged):
    def onStart(self):
        self.addForm('MAIN', CommandForm, name="Command Output")

if __name__ == '__main__':
    app = CommandApp()
    app.run()
