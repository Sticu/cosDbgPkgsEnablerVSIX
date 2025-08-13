using EnvDTE;
using Microsoft.VisualStudio.PlatformUI;
using System.Diagnostics;
using System.IO;
using System.Text;
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

        private void ProgressDlg_Loaded(object sender, RoutedEventArgs e)
        {
            //The way to refer to the embedded resource: {DefaultNamespace}.{Folder}.{FileName}; please keep updated!
            _scriptPath = ExtractResourceToTempFile(typeof(ProgressDlg).Namespace + ".Resources.mkDBGpkgs.ps1");

            this.ProgressOperationRunning.Visibility = Visibility.Hidden;
            this.OperationRunningIndicator.Visibility = Visibility.Hidden;

            // Start the long-running action when the dialog is loaded
            //await RunLongRunningActionAsync();
            IsCloseButtonEnabled = true;
        }

        private async Task RunLongRunningActionAsync()
        {
            // (for now) Simulate a long-running operation
            for (int i = 0; i <= 99; i += 10)
            {
                // (!) Switch to UI thread before updating UI elements
                await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
                OperationRunningIndicator.Value = i;
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
            bool bForceCheckAll = this.ChkboxForceCheckAllPackages.IsChecked ?? false;
            this.DebugifyBtn.IsEnabled = false;
            _ = ThreadHelper.JoinableTaskFactory.RunAsync(async () => await ExecutePowerShellScriptAsync(bForceCheckAll));
        }

        /// <summary>
        /// Execute the PowerShell script asynchronously, displaying its output in the text box.
        /// </summary>
        /// <param name="bForceCheckAll">TRUE if forcing handling all packages, FALSE otherwise</param>
        private async Task ExecutePowerShellScriptAsync(bool bForceCheckAll)
        {
            this.ProgressOperationRunning.Visibility = Visibility.Visible;
            this.OperationRunningIndicator.Visibility = Visibility.Visible;
            this.ProgressOperationRunning.IsIndeterminate = true;
            this.OperationRunningIndicator.IsIndeterminate = true;

            // Clear previous output
            await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
            CmdsExecOutput.Text = "Starting execution ...\r\n";
            IsCloseButtonEnabled = false;

            string ps1arguments = $"\"{_scriptPath}\" -csprojfile \"{_csprojName}\"" + (bForceCheckAll ? " -forceCheckAll" : string.Empty);

            var psi = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = $"-ExecutionPolicy Bypass -File {ps1arguments}",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using (var process = new System.Diagnostics.Process())
            {
                process.StartInfo = psi;

                // Set up event handlers for output
                StringBuilder outputBuilder = new StringBuilder();
                StringBuilder errorBuilder = new StringBuilder();

                process.OutputDataReceived += (sender, args) =>
                {
                    if (!string.IsNullOrEmpty(args.Data))
                    {
                        outputBuilder.AppendLine(args.Data);
                        ThreadHelper.JoinableTaskFactory.Run(async delegate
                        {
                            await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
                            CmdsExecOutput.Text = outputBuilder.ToString();
                            CmdsExecOutput.ScrollToEnd();
                        });
                    }
                };

                process.ErrorDataReceived += (sender, args) =>
                {
                    if (!string.IsNullOrEmpty(args.Data))
                    {
                        //errorBuilder.AppendLine("ERROR: " + args.Data);
                        outputBuilder.AppendLine("ERROR: " + args.Data);
                        ThreadHelper.JoinableTaskFactory.Run(async delegate
                        {
                            await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
                            CmdsExecOutput.Text = outputBuilder.ToString();
                            CmdsExecOutput.ScrollToEnd();
                        });
                    }
                };

                // Start the process
                process.Start();

                // Begin asynchronous reading of output and error streams
                process.BeginOutputReadLine();
                process.BeginErrorReadLine();

                // Wait for the process to complete
                await Task.Run(() => process.WaitForExit());
            }

            await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
            this.DebugifyBtn.IsEnabled = true;
            IsCloseButtonEnabled = true;
            this.ProgressOperationRunning.IsIndeterminate = false;
            this.ProgressOperationRunning.Visibility = Visibility.Hidden;
            this.OperationRunningIndicator.IsIndeterminate = false;
            this.OperationRunningIndicator.Visibility = Visibility.Hidden;
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
