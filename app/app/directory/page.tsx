import { Search } from "lucide-react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"

// Mock employee data - this will be replaced with actual database queries
const employees = [
  {
    id: 1,
    name: "Jack Taylor",
    title: "Manager, IT HelpDesk",
    department: "IT Services Group",
    email: "jtaylor@workday.net",
    phone: "+1 972-655-0961",
    location: "Dallas, TX 75201",
    avatar: "",
    initials: "JT"
  },
  {
    id: 2,
    name: "Anthony Rizzo",
    title: "Director, Information Technology",
    department: "IT Services Group",
    email: "arizzo@workday.net",
    phone: "+1 972-655-0962",
    location: "Dallas, TX 75201",
    avatar: "",
    initials: "AR"
  },
  {
    id: 3,
    name: "Helen Meyer",
    title: "Manager, Workstation Support",
    department: "IT Services Group",
    email: "hmeyer@workday.net",
    phone: "+1 972-655-0963",
    location: "Dallas, TX 75201",
    avatar: "",
    initials: "HM"
  },
  {
    id: 4,
    name: "Jared Ellis",
    title: "Manager, IT HelpDesk",
    department: "IT Services Group",
    email: "jellis@workday.net",
    phone: "+1 972-655-0964",
    location: "Dallas, TX 75201",
    avatar: "",
    initials: "JE"
  },
  {
    id: 5,
    name: "Kevin Gibson",
    title: "Manager, Information Analysis",
    department: "IT Services Group",
    email: "kgibson@workday.net",
    phone: "+1 972-655-0965",
    location: "Dallas, TX 75201",
    avatar: "",
    initials: "KG"
  },
]

export default function DirectoryPage() {
  return (
    <div className="p-6 space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-3xl font-bold text-gray-900">Directory</h1>
        <p className="text-gray-600 mt-1">Find and connect with colleagues</p>
      </div>

      {/* Search */}
      <Card>
        <CardHeader>
          <CardTitle>Search People</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
            <Input
              type="search"
              placeholder="Search by name, title, or department..."
              className="pl-10"
            />
          </div>
        </CardContent>
      </Card>

      {/* Employee List */}
      <Card>
        <CardHeader>
          <CardTitle>People ({employees.length})</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            {employees.map((employee) => (
              <div
                key={employee.id}
                className="flex items-start gap-4 p-4 border border-gray-200 rounded-lg hover:border-workday-blue hover:shadow-md transition-all cursor-pointer"
              >
                <Avatar className="w-16 h-16">
                  <AvatarImage src={employee.avatar} alt={employee.name} />
                  <AvatarFallback className="bg-workday-blue text-white text-lg">
                    {employee.initials}
                  </AvatarFallback>
                </Avatar>
                
                <div className="flex-1">
                  <h3 className="text-lg font-semibold text-workday-blue hover:underline">
                    {employee.name}
                  </h3>
                  <p className="text-sm text-gray-900 font-medium mt-1">
                    {employee.title}
                  </p>
                  <p className="text-sm text-gray-600">{employee.department}</p>
                  
                  <div className="mt-3 space-y-1">
                    <div className="flex items-center gap-2 text-sm">
                      <span className="text-gray-500">Email:</span>
                      <a href={`mailto:${employee.email}`} className="text-workday-blue hover:underline">
                        {employee.email}
                      </a>
                    </div>
                    <div className="flex items-center gap-2 text-sm">
                      <span className="text-gray-500">Phone:</span>
                      <a href={`tel:${employee.phone}`} className="text-workday-blue hover:underline">
                        {employee.phone}
                      </a>
                    </div>
                    <div className="flex items-center gap-2 text-sm">
                      <span className="text-gray-500">Location:</span>
                      <span className="text-gray-900">{employee.location}</span>
                    </div>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
