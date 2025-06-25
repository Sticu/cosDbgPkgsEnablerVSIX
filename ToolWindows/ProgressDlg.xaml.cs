using EnvDTE;
using Microsoft.VisualStudio.PlatformUI;
using System.Diagnostics;
using System.IO;
using System.Windows;

namespace DbgPkgEnabler
{
    public partial class ProgressDlg : DialogWindow
    {
        private string _scriptPath;
        private string _csprojName;

        public ProgressDlg(string csprojName)
        {
            _csprojName = csprojName;
            InitializeComponent();
            Loaded += ProgressDlg_Loaded;
        }

        private async void ProgressDlg_Loaded(object sender, RoutedEventArgs e)
        {
            //The way to refer to the embedded resource: {DefaultNamespace}.{Folder}.{FileName}; please keep updated!
            _scriptPath = ExtractResourceToTempFile(typeof(ProgressDlg).Namespace + ".Resources.mkDBGpkgs.ps1");

            // Start the long-running action when the dialog is loaded
            await RunLongRunningActionAsync();
        }

        private async Task RunLongRunningActionAsync()
        {
            // (for now) Simulate a long-running operation
            for (int i = 0; i <= 100; i += 10)
            {
                // (!) Switch to UI thread before updating UI elements
                await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
                ProgressBar.Value = i;
                ProgressText.Text = $"{i}% completed";
                // Simulate work
                await Task.Delay(1000);
            }

            await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
            // Optionally close the dialog when done
            //this.Close();
        }

        private void CloseButton_Click(object sender, RoutedEventArgs e)
        {
            this.Close();
        }

        private void RunButton_Click(object sender, RoutedEventArgs e)
        {
            //string psCommand = "ls -Force";

            var psi = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                //Arguments = $"-NoProfile -Command \"{psCommand}\"",
                Arguments = $"-ExecutionPolicy Bypass -File \"{_scriptPath}\" -csprojfile \"{_csprojName}\" -forceCheckAll",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using (var process = System.Diagnostics.Process.Start(psi))
            {
                string output = process.StandardOutput.ReadToEnd();
                string error = process.StandardError.ReadToEnd();
                process.WaitForExit();

                // Do something with the output
                CmdsExecOutput.Text = !string.IsNullOrWhiteSpace(error) ? error : output;
            }

            //var process = new System.Diagnostics.Process { StartInfo = psi };
            //process.OutputDataReceived += (sender, e) =>
            //{
            //    if (!string.IsNullOrEmpty(e.Data))
            //    {
            //        _ = Task.Run(async () =>
            //        {
            //            await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
            //            CmdsExecOutput.AppendText(e.Data + "\n");
            //        });
            //    }
            //};
            //process.ErrorDataReceived += (sender, e) =>
            //{
            //    if (!string.IsNullOrEmpty(e.Data))
            //    {
            //        _ = Task.Run(async () =>
            //        {

            //            await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
            //            CmdsExecOutput.AppendText("ERROR: " + e.Data + "\n");
            //        });
            //    }
            //};
            //process.Start();
            //process.BeginOutputReadLine();
            //process.BeginErrorReadLine();
            //process.WaitForExit();
        }

        private string ExtractResourceToTempFile(string resourceName)
        {
            string[] parts = resourceName.Split('.');
            string fileName = (parts.Length < 2)
                                    ? resourceName
                                    : parts[parts.Length - 2] + "." + parts[parts.Length - 1];
            string filePath = Path.Combine(Path.GetTempPath(), fileName);

            var assembly = System.Reflection.Assembly.GetExecutingAssembly();

            using (Stream resourceStream = assembly.GetManifestResourceStream(resourceName))
            {
                if (resourceStream == null)
                {
                    return null;
                }

                using (StreamReader reader = new StreamReader(resourceStream))
                {
                    string content = reader.ReadToEnd();
                    File.WriteAllText(filePath, content);
                }
            }

            return filePath;
        }

    }
}
