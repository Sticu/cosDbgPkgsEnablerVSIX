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

            this.ProgressOperationRunning.Visibility = Visibility.Hidden;

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

        private void DebugifyButton_Click(object sender, RoutedEventArgs e)
        {
            this.DebugifyBtn.IsEnabled = false;
            _ = ThreadHelper.JoinableTaskFactory.RunAsync(async () => await ExecutePowerShellScriptAsync(true));
        }

        private async Task ExecutePowerShellScriptAsync(bool bForceCheckAll)
        {
            this.ProgressOperationRunning.Visibility = Visibility.Visible;
            this.ProgressOperationRunning.IsIndeterminate = true;
            string output = string.Empty;
            string error = string.Empty;
            // This method can be used to execute the PowerShell script asynchronously if needed
            await Task.Run(() =>
            {
                string ps1arguments = $"\"{_scriptPath}\" -csprojfile \"{_csprojName}\"" + (bForceCheckAll ? " -forceCheckAll" : string.Empty);
                var psi = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    //Arguments = $"-ExecutionPolicy Bypass -File \"{_scriptPath}\" -csprojfile \"{_csprojName}\" -forceCheckAll",
                    Arguments = $"-ExecutionPolicy Bypass -File " + ps1arguments,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };

                using (var process = System.Diagnostics.Process.Start(psi))
                {
                    output = process.StandardOutput.ReadToEnd();
                    error = process.StandardError.ReadToEnd();
                    process.WaitForExit();

                    // Do something with the output
                    //CmdsExecOutput.Text = !string.IsNullOrWhiteSpace(error) ? error : output;
                }
            });

            await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
            CmdsExecOutput.Text = !string.IsNullOrWhiteSpace(error) ? error : output;
            this.DebugifyBtn.IsEnabled = true;
            this.ProgressOperationRunning.IsIndeterminate = false;
            this.ProgressOperationRunning.Visibility = Visibility.Hidden;
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
