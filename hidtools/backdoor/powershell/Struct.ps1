$structclass = New-Object psobject -Property @{
    
}

$structclass | Add-Member -Force -MemberType ScriptMethod -Name "extractNullTerminatedString" -Value {
    param(
          [Parameter(Mandatory=$true)]
          [Byte[]] $data
    )

    # check if 0x00 is present as terminator
    if (-not $data.Contains([Byte]0))
    {
        return "" # return empty string
    }

    # detect position of 0x00
    $end = $data.IndexOf([Byte]0)

    # extract string
    $str = $data[0..($end-1)]

    #conver to UTF8
    $str = [System.Text.Encoding]::UTF8.GetString($str, 0, $str.Length)

    # extract remaining data
    $remainder = $data[($end+1)..($data.Length-1)]

    # return String and remainder as array
    return ($str, [Byte[]]$remainder)
}

$structclass | Add-Member -Force -MemberType ScriptMethod -Name "packString" -Value {
    param(
          [Parameter(Mandatory=$false)]
          [String] $str,

          [Parameter(Mandatory=$true)]
          [Byte[]] $data
    )

    #convert UTF8 to Byte[] and append 0x00
    $new_data = [System.Text.Encoding]::UTF8.GetBytes($str)
    $new_data = [Byte[]] ($new_data + 0) # add null termination
    
    if ($data)
    {
        return [Byte[]]($data + $new_data)
    }
    else
    {
        return [Byte[]] $new_data
    }
    
}

$structclass | Add-Member -Force -MemberType ScriptMethod -Name "packUInt32" -Value {
    param(
          [Parameter(Mandatory=$true)]
          [UInt32] $uint,

          [Parameter(Mandatory=$true)]
          [Byte[]] $data
    )

    #convert UTF8 to Byte[] and append 0x00
    $new_data = [System.BitConverter]::GetBytes($uint)
    if ([System.BitConverter]::IsLittleEndian) { [array]::Reverse($new_data) }
    
    
    if ($data)
    {
        return [Byte[]]($data + $new_data)
    }
    else
    {
        return [Byte[]] $new_data
    }
    
}

$structclass | Add-Member -Force -MemberType ScriptMethod -Name "packByte" -Value {
    param(
          [Parameter(Mandatory=$true)]
          [Byte] $ubyte,

          [Parameter(Mandatory=$true)]
          [Byte[]] $data
    )

    #convert UTF8 to Byte[] and append 0x00
    $new_data = $ubyte
    
    
    
    if ($data)
    {
        return [Byte[]]($data + $new_data)
    }
    else
    {
        return [Byte[]] $new_data
    }
    
}


$structclass | Add-Member -Force -MemberType ScriptMethod -Name "extractUInt32" -Value {
    param(
          [Parameter(Mandatory=$true)]
          [Byte[]] $data
    )

    $val = $data[0..3]
    # account for endianess (we receive Network order)
    if ([System.BitConverter]::IsLittleEndian) { [array]::Reverse($val) }
    $val = [BitConverter]::ToUInt32($val, 0)

    $remainder = $data[4..($data.Length)]


    # return unint32 and remainder as array
    return ($val, [Byte[]]$remainder)
}