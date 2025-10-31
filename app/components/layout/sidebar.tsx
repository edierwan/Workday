"use client"

import Link from "next/link"
import { usePathname } from "next/navigation"
import { 
  Home, 
  Users, 
  DollarSign, 
  FileText, 
  Calendar, 
  Award, 
  BarChart3,
  Briefcase,
  Heart,
  HelpCircle
} from "lucide-react"
import { cn } from "@/lib/utils"

const menuItems = [
  { icon: Home, label: "Home", href: "/" },
  { icon: Users, label: "Directory", href: "/directory" },
  { icon: DollarSign, label: "Pay", href: "/pay" },
  { icon: Heart, label: "Benefits", href: "/benefits" },
  { icon: Calendar, label: "Absence", href: "/absence" },
  { icon: FileText, label: "Personal Information", href: "/personal" },
  { icon: Award, label: "Performance", href: "/performance" },
  { icon: Briefcase, label: "Career", href: "/career" },
  { icon: BarChart3, label: "Analytics", href: "/analytics" },
  { icon: HelpCircle, label: "Help", href: "/help" },
]

export function Sidebar() {
  const pathname = usePathname()

  return (
    <aside className="hidden md:flex w-64 bg-white border-r border-gray-200 flex-col">
      <div className="p-6">
        <Link href="/" className="flex items-center gap-2">
          <div className="w-8 h-8 bg-workday-blue rounded-md flex items-center justify-center">
            <span className="text-white font-bold text-lg">W</span>
          </div>
          <span className="text-xl font-semibold text-gray-900">Workday</span>
        </Link>
      </div>

      <nav className="flex-1 px-3 space-y-1">
        {menuItems.map((item) => {
          const Icon = item.icon
          const isActive = pathname === item.href
          
          return (
            <Link
              key={item.href}
              href={item.href}
              className={cn(
                "flex items-center gap-3 px-3 py-2.5 text-sm font-medium rounded-md transition-colors",
                isActive
                  ? "bg-workday-blue text-white"
                  : "text-gray-700 hover:bg-gray-100 hover:text-gray-900"
              )}
            >
              <Icon className="w-5 h-5" />
              <span>{item.label}</span>
            </Link>
          )
        })}
      </nav>

      <div className="p-4 border-t border-gray-200">
        <p className="text-xs text-gray-500 text-center">
          © 2025 Workday HRMS
        </p>
      </div>
    </aside>
  )
}
