using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using GHelper.Mode;
using Microsoft.Win32.SafeHandles;

namespace GHelper.IPC
{
    public static class PipeServer
    {
        private const string PipeName = @"\\.\pipe\GHelper_IPC";
        private static CancellationTokenSource? _cts;

        [StructLayout(LayoutKind.Sequential)]
        private struct SECURITY_ATTRIBUTES
        {
            public int nLength;
            public IntPtr lpSecurityDescriptor;
            public bool bInheritHandle;
        }

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern SafePipeHandle CreateNamedPipeW(
            string lpName,
            uint dwOpenMode,
            uint dwPipeMode,
            uint nMaxInstances,
            uint nOutBufferSize,
            uint nInBufferSize,
            uint nDefaultTimeOut,
            ref SECURITY_ATTRIBUTES lpSecurityAttributes);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool ConnectNamedPipe(SafePipeHandle hNamedPipe, IntPtr lpOverlapped);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool DisconnectNamedPipe(SafePipeHandle hNamedPipe);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool ReadFile(SafePipeHandle hFile, byte[] lpBuffer, uint nNumberOfBytesToRead, out uint lpNumberOfBytesRead, IntPtr lpOverlapped);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool WriteFile(SafePipeHandle hFile, byte[] lpBuffer, uint nNumberOfBytesToWrite, out uint lpNumberOfBytesWritten, IntPtr lpOverlapped);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool InitializeSecurityDescriptor(IntPtr pSecurityDescriptor, uint dwRevision);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool SetSecurityDescriptorDacl(IntPtr pSecurityDescriptor, bool bDaclPresent, IntPtr pDacl, bool bDaclDefaulted);

        private const uint PIPE_ACCESS_DUPLEX = 0x00000003;
        private const uint PIPE_TYPE_BYTE = 0x00000000;
        private const uint PIPE_READMODE_BYTE = 0x00000000;
        private const uint PIPE_WAIT = 0x00000000;
        private const uint SECURITY_DESCRIPTOR_REVISION = 1;

        public static void Start()
        {
            _cts = new CancellationTokenSource();
            Task.Run(() => ListenLoop(_cts.Token));
            Logger.WriteLine("IPC Pipe Server started");
        }

        public static void Stop()
        {
            _cts?.Cancel();
            Logger.WriteLine("IPC Pipe Server stopped");
        }

        private static SafePipeHandle CreatePipeWithEveryoneAccess()
        {
            IntPtr sd = Marshal.AllocHGlobal(4096);
            try
            {
                if (!InitializeSecurityDescriptor(sd, SECURITY_DESCRIPTOR_REVISION))
                {
                    Logger.WriteLine("IPC: InitializeSecurityDescriptor failed: " + Marshal.GetLastWin32Error());
                    return new SafePipeHandle(IntPtr.Zero, true);
                }

                // NULL DACL = no access control, everyone can connect
                if (!SetSecurityDescriptorDacl(sd, true, IntPtr.Zero, false))
                {
                    Logger.WriteLine("IPC: SetSecurityDescriptorDacl failed: " + Marshal.GetLastWin32Error());
                    return new SafePipeHandle(IntPtr.Zero, true);
                }

                var sa = new SECURITY_ATTRIBUTES();
                sa.nLength = Marshal.SizeOf(sa);
                sa.lpSecurityDescriptor = sd;
                sa.bInheritHandle = false;

                var handle = CreateNamedPipeW(
                    PipeName,
                    PIPE_ACCESS_DUPLEX,
                    PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
                    1,
                    4096,
                    4096,
                    0,
                    ref sa);

                if (handle.IsInvalid)
                    Logger.WriteLine("IPC: CreateNamedPipe failed: " + Marshal.GetLastWin32Error());

                return handle;
            }
            finally
            {
                Marshal.FreeHGlobal(sd);
            }
        }

        private static void ListenLoop(CancellationToken ct)
        {
            while (!ct.IsCancellationRequested)
            {
                SafePipeHandle? handle = null;
                try
                {
                    handle = CreatePipeWithEveryoneAccess();
                    if (handle.IsInvalid)
                    {
                        Logger.WriteLine("IPC: Invalid pipe handle, retrying...");
                        Thread.Sleep(1000);
                        continue;
                    }

                    Logger.WriteLine("IPC: Waiting for connection...");

                    if (!ConnectNamedPipe(handle, IntPtr.Zero))
                    {
                        int err = Marshal.GetLastWin32Error();
                        if (err == 535) // ERROR_PIPE_CONNECTED - already connected, OK
                        { }
                        else if (err == 995) // ERROR_OPERATION_ABORTED - cancelled
                        {
                            break;
                        }
                        else
                        {
                            Logger.WriteLine("IPC: ConnectNamedPipe failed: " + err);
                            handle.Close();
                            Thread.Sleep(1000);
                            continue;
                        }
                    }

                    Logger.WriteLine("IPC: Client connected");
                    HandleClient(handle);
                }
                catch (OperationCanceledException)
                {
                    break;
                }
                catch (Exception ex)
                {
                    Logger.WriteLine("IPC Error: " + ex.Message);
                    Thread.Sleep(1000);
                }
                finally
                {
                    try { handle?.Close(); } catch { }
                }
            }
        }

        private static void HandleClient(SafePipeHandle handle)
        {
            try
            {
                var buffer = new byte[4096];
                if (!ReadFile(handle, buffer, (uint)buffer.Length, out uint bytesRead, IntPtr.Zero) || bytesRead == 0)
                {
                    Logger.WriteLine("IPC: ReadFile failed: " + Marshal.GetLastWin32Error());
                    return;
                }

                string request = Encoding.UTF8.GetString(buffer, 0, (int)bytesRead).Trim();
                Logger.WriteLine("IPC Request: " + request);

                string response = ProcessCommand(request);

                byte[] responseBytes = Encoding.UTF8.GetBytes(response);
                if (!WriteFile(handle, responseBytes, (uint)responseBytes.Length, out _, IntPtr.Zero))
                {
                    Logger.WriteLine("IPC: WriteFile failed: " + Marshal.GetLastWin32Error());
                }
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch (Exception ex)
            {
                Logger.WriteLine("IPC HandleClient Error: " + ex.Message);
            }
            finally
            {
                try { DisconnectNamedPipe(handle); } catch { }
            }
        }

        private static string ProcessCommand(string request)
        {
            try
            {
                var json = JsonDocument.Parse(request);
                string? command = json.RootElement.GetProperty("command").GetString();

                return command?.ToLower() switch
                {
                    "set_mode" => HandleSetMode(json.RootElement),
                    "get_mode" => HandleGetMode(),
                    "get_modes" => HandleGetModes(),
                    _ => ErrorResponse("Unknown command: " + command)
                };
            }
            catch (Exception ex)
            {
                return ErrorResponse("Invalid request: " + ex.Message);
            }
        }

        private static string HandleSetMode(JsonElement root)
        {
            try
            {
                int modeIndex = -1;

                if (root.TryGetProperty("mode", out var modeProp))
                {
                    if (modeProp.ValueKind == JsonValueKind.Number)
                    {
                        modeIndex = modeProp.GetInt32();
                    }
                    else if (modeProp.ValueKind == JsonValueKind.String)
                    {
                        string? modeName = modeProp.GetString();
                        modeIndex = FindModeByName(modeName);
                        if (modeIndex < 0)
                            return ErrorResponse("Mode not found: " + modeName);
                    }
                }
                else
                {
                    return ErrorResponse("Missing 'mode' parameter");
                }

                if (!Modes.Exists(modeIndex))
                    return ErrorResponse("Invalid mode index: " + modeIndex);

                Program.modeControl.SetPerformanceMode(modeIndex, notify: true);

                return SuccessResponse(new
                {
                    mode = modeIndex,
                    name = Modes.GetName(modeIndex)
                });
            }
            catch (Exception ex)
            {
                return ErrorResponse(ex.Message);
            }
        }

        private static string HandleGetMode()
        {
            int current = Modes.GetCurrent();
            return SuccessResponse(new
            {
                mode = current,
                name = Modes.GetName(current),
                baseMode = Modes.GetCurrentBase()
            });
        }

        private static string HandleGetModes()
        {
            var modes = Modes.GetDictonary();
            var list = modes.Select(m => new
            {
                index = m.Key,
                name = m.Value,
                isCurrent = m.Key == Modes.GetCurrent()
            }).ToArray();

            return SuccessResponse(new { modes = list });
        }

        private static int FindModeByName(string? name)
        {
            if (string.IsNullOrEmpty(name)) return -1;

            var modes = Modes.GetDictonary();
            foreach (var mode in modes)
            {
                if (string.Equals(mode.Value, name, StringComparison.OrdinalIgnoreCase))
                    return mode.Key;
            }

            if (int.TryParse(name, out int index))
                return index;

            return name.ToLower() switch
            {
                "silent" or "quiet" => AsusACPI.PerformanceSilent,
                "balanced" or "normal" => AsusACPI.PerformanceBalanced,
                "turbo" or "performance" => AsusACPI.PerformanceTurbo,
                _ => -1
            };
        }

        private static string SuccessResponse(object data)
        {
            return JsonSerializer.Serialize(new { success = true, data });
        }

        private static string ErrorResponse(string message)
        {
            return JsonSerializer.Serialize(new { success = false, error = message });
        }
    }
}
