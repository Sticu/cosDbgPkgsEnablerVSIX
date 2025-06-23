using Microsoft.VisualStudio.PlatformUI;
using System.Windows;

namespace DbgPkgEnabler
{
    public partial class ProgressDlg : DialogWindow
    {
        public ProgressDlg()
        {
            InitializeComponent();
            Loaded += ProgressDlg_Loaded;
        }

        private async void ProgressDlg_Loaded(object sender, RoutedEventArgs e)
        {
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
                await Task.Delay(500);
            }

            await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
            // Optionally close the dialog when done
            Button_Click(this, new RoutedEventArgs());
        }

        private void Button_Click(object sender, RoutedEventArgs e)
        {
            this.Close();
        }
    }
}
