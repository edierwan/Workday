import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"

export default function AbsencePage() {
  return (
    <div className="p-6 space-y-6">
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-3xl font-bold text-gray-900">Absence</h1>
          <p className="text-gray-600 mt-1">Request and manage time off</p>
        </div>
        <Button>Request Time Off</Button>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <Card>
          <CardHeader>
            <CardTitle>Available Balance</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-2">
              <div className="flex justify-between items-center">
                <span className="text-gray-600">Annual Leave</span>
                <span className="font-semibold text-lg">15 days</span>
              </div>
              <div className="flex justify-between items-center">
                <span className="text-gray-600">Sick Leave</span>
                <span className="font-semibold text-lg">10 days</span>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Upcoming Time Off</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-sm text-gray-600">No upcoming time off scheduled</p>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
