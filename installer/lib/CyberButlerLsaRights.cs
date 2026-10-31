using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Security.Principal;

namespace CyberButler
{
    public static class LsaRights
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct LSA_UNICODE_STRING
        {
            public ushort Length;
            public ushort MaximumLength;
            public IntPtr Buffer;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct LSA_OBJECT_ATTRIBUTES
        {
            public int Length;
            public IntPtr RootDirectory;
            public IntPtr ObjectName;
            public uint Attributes;
            public IntPtr SecurityDescriptor;
            public IntPtr SecurityQualityOfService;
        }

        private const uint POLICY_ALL_ACCESS = 0x00F0FFF;
        private const uint STATUS_OBJECT_NAME_NOT_FOUND = 0xC0000034;

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern uint LsaOpenPolicy(
            IntPtr SystemName,
            ref LSA_OBJECT_ATTRIBUTES ObjectAttributes,
            uint DesiredAccess,
            out IntPtr PolicyHandle);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern uint LsaAddAccountRights(
            IntPtr PolicyHandle,
            byte[] AccountSid,
            [MarshalAs(UnmanagedType.LPArray)] LSA_UNICODE_STRING[] UserRights,
            uint CountOfRights);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern uint LsaEnumerateAccountRights(
            IntPtr PolicyHandle,
            byte[] AccountSid,
            out IntPtr UserRights,
            out uint CountOfRights);

        [DllImport("advapi32.dll")]
        private static extern uint LsaFreeMemory(IntPtr Buffer);

        [DllImport("advapi32.dll")]
        private static extern uint LsaClose(IntPtr ObjectHandle);

        [DllImport("advapi32.dll")]
        private static extern uint LsaNtStatusToWinError(uint Status);

        private static IntPtr OpenPolicy()
        {
            LSA_OBJECT_ATTRIBUTES attributes = new LSA_OBJECT_ATTRIBUTES();
            attributes.Length = Marshal.SizeOf(typeof(LSA_OBJECT_ATTRIBUTES));
            IntPtr handle;
            uint status = LsaOpenPolicy(IntPtr.Zero, ref attributes, POLICY_ALL_ACCESS, out handle);
            if (status != 0)
            {
                throw new InvalidOperationException("LsaOpenPolicy failed: Win32 " + LsaNtStatusToWinError(status));
            }
            return handle;
        }

        private static byte[] SidBytes(string sid)
        {
            SecurityIdentifier identifier = new SecurityIdentifier(sid);
            byte[] bytes = new byte[identifier.BinaryLength];
            identifier.GetBinaryForm(bytes, 0);
            return bytes;
        }

        public static void AddRights(string sid, string[] rights)
        {
            if (rights == null || rights.Length == 0) { return; }
            IntPtr policy = OpenPolicy();
            IntPtr[] buffers = new IntPtr[rights.Length];
            try
            {
                LSA_UNICODE_STRING[] values = new LSA_UNICODE_STRING[rights.Length];
                for (int i = 0; i < rights.Length; i++)
                {
                    buffers[i] = Marshal.StringToHGlobalUni(rights[i]);
                    values[i] = new LSA_UNICODE_STRING
                    {
                        Buffer = buffers[i],
                        Length = (ushort)(rights[i].Length * 2),
                        MaximumLength = (ushort)((rights[i].Length + 1) * 2)
                    };
                }
                uint status = LsaAddAccountRights(policy, SidBytes(sid), values, (uint)values.Length);
                if (status != 0)
                {
                    throw new InvalidOperationException("LsaAddAccountRights failed: Win32 " + LsaNtStatusToWinError(status));
                }
            }
            finally
            {
                foreach (IntPtr buffer in buffers)
                {
                    if (buffer != IntPtr.Zero) { Marshal.FreeHGlobal(buffer); }
                }
                LsaClose(policy);
            }
        }

        public static string[] GetRights(string sid)
        {
            IntPtr policy = OpenPolicy();
            IntPtr rightsPointer = IntPtr.Zero;
            try
            {
                uint count;
                uint status = LsaEnumerateAccountRights(policy, SidBytes(sid), out rightsPointer, out count);
                if (status == STATUS_OBJECT_NAME_NOT_FOUND) { return new string[0]; }
                if (status != 0)
                {
                    throw new InvalidOperationException("LsaEnumerateAccountRights failed: Win32 " + LsaNtStatusToWinError(status));
                }
                List<string> result = new List<string>();
                int size = Marshal.SizeOf(typeof(LSA_UNICODE_STRING));
                for (uint i = 0; i < count; i++)
                {
                    IntPtr item = IntPtr.Add(rightsPointer, (int)i * size);
                    LSA_UNICODE_STRING value = (LSA_UNICODE_STRING)Marshal.PtrToStructure(item, typeof(LSA_UNICODE_STRING));
                    if (value.Buffer != IntPtr.Zero && value.Length > 0)
                    {
                        result.Add(Marshal.PtrToStringUni(value.Buffer, value.Length / 2));
                    }
                }
                return result.ToArray();
            }
            finally
            {
                if (rightsPointer != IntPtr.Zero) { LsaFreeMemory(rightsPointer); }
                LsaClose(policy);
            }
        }
    }
}
