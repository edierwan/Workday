import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Inbox, Calendar, Users, DollarSign, TrendingUp, Briefcase } from "lucide-react"

export default function HomePage() {
  const today = new Date().toLocaleDateString('en-US', { 
    weekday: 'long', 
    year: 'numeric', 
    month: 'long', 
    day: 'numeric' 
  })

  return (
    <div className="p-6 space-y-6">
      {/* Greeting Section */}
      <div className="bg-gradient-to-r from-workday-blue to-workday-dark-blue text-white rounded-lg p-8">
        <h1 className="text-3xl font-bold mb-2">Good Afternoon, Brian Kaplan</h1>
        <p className="text-blue-100">It's {today}</p>
      </div>

      {/* Awaiting Your Action */}
      <Card>
        <CardHeader>
          <CardTitle>Awaiting Your Action</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-start gap-4 p-4 bg-gray-50 rounded-lg hover:bg-gray-100 transition-colors cursor-pointer">
            <div className="w-12 h-12 bg-blue-100 rounded-lg flex items-center justify-center flex-shrink-0">
              <Inbox className="w-6 h-6 text-workday-blue" />
            </div>
            <div className="flex-1">
              <h3 className="font-semibold text-gray-900">Self Evaluation: Ad hoc Review - Goals: Brian Kaplan</h3>
              <p className="text-sm text-gray-600 mt-1">Inbox • 48 minute(s) ago</p>
              <p className="text-sm text-red-600 font-medium mt-1">DUE 08/24/2022</p>
            </div>
          </div>

          <div className="flex items-start gap-4 p-4 bg-gray-50 rounded-lg hover:bg-gray-100 transition-colors cursor-pointer">
            <div className="w-12 h-12 bg-blue-100 rounded-lg flex items-center justify-center flex-shrink-0">
              <Calendar className="w-6 h-6 text-workday-blue" />
            </div>
            <div className="flex-1">
              <h3 className="font-semibold text-gray-900">Building Belonging</h3>
              <p className="text-sm text-gray-600 mt-1">Journey • In progress</p>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Quick Access Apps */}
      <div>
        <h2 className="text-xl font-semibold mb-4">Quick Access</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <Card className="hover:shadow-lg transition-shadow cursor-pointer">
            <CardHeader className="flex flex-row items-center gap-4 pb-2">
              <div className="w-12 h-12 bg-blue-100 rounded-lg flex items-center justify-center">
                <DollarSign className="w-6 h-6 text-workday-blue" />
              </div>
              <CardTitle className="text-base">Pay</CardTitle>
            </CardHeader>
            <CardContent>
              <CardDescription>View pay slips and tax documents</CardDescription>
            </CardContent>
          </Card>

          <Card className="hover:shadow-lg transition-shadow cursor-pointer">
            <CardHeader className="flex flex-row items-center gap-4 pb-2">
              <div className="w-12 h-12 bg-green-100 rounded-lg flex items-center justify-center">
                <Calendar className="w-6 h-6 text-green-600" />
              </div>
              <CardTitle className="text-base">Time Off</CardTitle>
            </CardHeader>
            <CardContent>
              <CardDescription>Request and manage time off</CardDescription>
            </CardContent>
          </Card>

          <Card className="hover:shadow-lg transition-shadow cursor-pointer">
            <CardHeader className="flex flex-row items-center gap-4 pb-2">
              <div className="w-12 h-12 bg-purple-100 rounded-lg flex items-center justify-center">
                <Users className="w-6 h-6 text-purple-600" />
              </div>
              <CardTitle className="text-base">Directory</CardTitle>
            </CardHeader>
            <CardContent>
              <CardDescription>Find colleagues and teams</CardDescription>
            </CardContent>
          </Card>

          <Card className="hover:shadow-lg transition-shadow cursor-pointer">
            <CardHeader className="flex flex-row items-center gap-4 pb-2">
              <div className="w-12 h-12 bg-orange-100 rounded-lg flex items-center justify-center">
                <Briefcase className="w-6 h-6 text-workday-orange" />
              </div>
              <CardTitle className="text-base">Career Hub</CardTitle>
            </CardHeader>
            <CardContent>
              <CardDescription>Explore career opportunities</CardDescription>
            </CardContent>
          </Card>
        </div>
      </div>

      {/* Announcements */}
      <Card>
        <CardHeader>
          <CardTitle>Announcements</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex gap-4 p-4 border border-gray-200 rounded-lg">
            <div className="w-20 h-20 bg-blue-100 rounded-lg flex items-center justify-center flex-shrink-0">
              <Users className="w-10 h-10 text-workday-blue" />
            </div>
            <div className="flex-1">
              <h3 className="font-semibold text-gray-900 mb-1">
                Help Us to Create a Great Place to Work for ALL
              </h3>
              <p className="text-sm text-gray-600">
                We are committed to creating a great place to work...
              </p>
            </div>
          </div>

          <div className="flex gap-4 p-4 border border-gray-200 rounded-lg">
            <div className="w-20 h-20 bg-red-100 rounded-lg flex items-center justify-center flex-shrink-0">
              <TrendingUp className="w-10 h-10 text-red-600" />
            </div>
            <div className="flex-1">
              <h3 className="font-semibold text-gray-900 mb-1">
                COVID-19 Vaccines Are Here
              </h3>
              <p className="text-sm text-gray-600">
                Important information about COVID-19 vaccinations...
              </p>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
