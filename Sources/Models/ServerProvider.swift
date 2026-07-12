import Foundation
import SwiftUI

public enum ServerProvider: String, CaseIterable, Identifiable, Hashable {
    case amazonEC2
    case digitalOcean
    case hetzner
    case linode
    case gcp
    case azure
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .amazonEC2: return "Amazon EC2"
        case .digitalOcean: return "DigitalOcean"
        case .hetzner: return "Hetzner Cloud"
        case .linode: return "Linode / Akamai"
        case .gcp: return "Google Compute"
        case .azure: return "Azure VM"
        case .custom: return "Custom SSH"
        }
    }

    public var subtitle: String {
        switch self {
        case .amazonEC2: return "Connect to an EC2 instance with SSH key"
        case .digitalOcean: return "Droplet over SSH — root + key"
        case .hetzner: return "Cloud server — root access"
        case .linode: return "Linode instance over SSH"
        case .gcp: return "Compute Engine VM"
        case .azure: return "Linux or Windows SSH endpoint"
        case .custom: return "Any host, port, and credentials"
        }
    }

    public var systemImage: String {
        switch self {
        case .amazonEC2: return "cloud.fill"
        case .digitalOcean: return "drop.fill"
        case .hetzner: return "server.rack"
        case .linode: return "cylinder.split.1x2.fill"
        case .gcp: return "globe.americas.fill"
        case .azure: return "square.stack.3d.up.fill"
        case .custom: return "terminal.fill"
        }
    }

    public var hostPlaceholder: String {
        switch self {
        case .amazonEC2: return "ec2-12-34-56-78.compute-1.amazonaws.com"
        case .digitalOcean: return "164.90.xxx.xxx"
        case .hetzner: return "xxx.xxx.xxx.xxx"
        case .linode: return "xxx.xxx.xxx.xxx"
        case .gcp: return "xxx.xxx.xxx.xxx"
        case .azure: return "myvm.eastus.cloudapp.azure.com"
        case .custom: return "hostname or IP"
        }
    }

    public var suggestedUsername: String {
        switch self {
        case .amazonEC2: return "ubuntu"
        case .digitalOcean, .hetzner, .linode: return "root"
        case .gcp: return "ubuntu"
        case .azure: return "azureuser"
        case .custom: return "root"
        }
    }

    public var preferredAuth: Server.AuthMethod {
        switch self {
        case .custom: return .password
        default: return .sshKey
        }
    }

    public var tip: String {
        switch self {
        case .amazonEC2:
            return "Amazon Linux often uses ec2-user. Ubuntu AMIs use ubuntu. Prefer the .pem key from the key pair."
        case .digitalOcean:
            return "Add your public key in DigitalOcean → Settings → Security before connecting."
        case .hetzner:
            return "Use the IPv4 from the Hetzner Cloud Console. Root login with SSH key is default."
        case .linode:
            return "Enable SSH key auth when creating the Linode, or add keys under Account → SSH Keys."
        case .gcp:
            return "Ensure the VM allows SSH on port 22 and your project SSH keys are provisioned."
        case .azure:
            return "Use the DNS name or public IP from the Azure portal. Port is usually 22."
        case .custom:
            return "Enter any reachable SSH host. Password or private key both work."
        }
    }

    public var defaultName: String {
        "\(title) Server"
    }
}
