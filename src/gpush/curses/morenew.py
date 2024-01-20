import npyscreen
import subprocess

class CommandForm(npyscreen.Form):
    def afterEditing(self):
        self.parentApp.setNextForm(None)

    def create(self):
        self.add(npyscreen.TitleText, name="Command Output:")
        # Execute the first command and capture stdout and stderr
        process1 = subprocess.Popen(["./sleepy.sh"], #, "arg1", "arg2"],
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        stdout1, stderr1 = process1.communicate()
        self.add(npyscreen.MultiLineEdit, value=str(stdout1), editable=False)
        if stderr1:
            error_widget = self.add(npyscreen.MultiLineEdit, value=str(stderr1), editable=False)
            error_widget.color = 'DANGER'
            # Execute the second command and capture stdout and stderr
        process2 = subprocess.Popen(["./sleepy.sh"],
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        stdout2, stderr2 = process2.communicate()

        self.add(npyscreen.MultiLineEdit, value=str(stdout2), editable=False)
        if stderr2:
            error_widget = self.add(npyscreen.MultiLineEdit, value=str(stderr2), editable=False)
            error_widget.color = 'DANGER'

class CommandApp(npyscreen.NPSAppManaged):
    def onStart(self):
        self.addForm('MAIN', CommandForm, name="Command Output")

if __name__ == '__main__':
    app = CommandApp()
    app.run()
